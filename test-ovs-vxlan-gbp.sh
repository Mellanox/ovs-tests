#!/bin/bash
#
# Test ovs rules to enacp/decap vxlan gbp option can be offloaded correctly
# with vxlan traffic.
#
# RM 3291721 VxLAN GBP offload
#
# 1. Config vxlan and enable gbp
# 2. Add ovs rules to encap gbp option to vxlan traffic
# 3. Send traffic over vxlan
# 4. Check the traffic is offloaded correctly
#    On remote, ip table rule for output will add gbp option to ip packets
#    On local, tc rules will encap gbp option to ip packets and filter packets
#    according to gbp option
#
# This test needs kernel 5.5+
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42
DSTPORT=4789
GBP_OPT_OUT="0x200"
GBP_OPT_IN="0x400"
VXLAN_OPTIONS="gbp"

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

function cleanup_remote() {
    cleanup_remote_vxlan
    on_remote "iptables -D OUTPUT -p ip -j MARK --set-mark $GBP_OPT_IN 2>/dev/null
               iptables -D INPUT -m mark --mark $GBP_OPT_OUT -j ACCEPT 2>/dev/null"
}

function cleanup_local() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ovs_clear_bridges
    reset_tc $REP
}

function cleanup() {
    cleanup_local
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config_remote() {
    config_remote_vxlan
    on_remote "iptables -I OUTPUT -p ip -j MARK --set-mark $GBP_OPT_IN
               iptables -I INPUT -m mark --mark $GBP_OPT_OUT -j ACCEPT"
}

function config_local() {
    cleanup
    ifconfig $NIC $LOCAL_TUN/24 up
    ip netns add ns0
    config_vf ns0 $VF $REP $IP

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP \
	    options:key=$VXLAN_ID options:dst_port=$DSTPORT options:csum=true options:exts=gbp

    # GBP rules
    ovs-ofctl add-flow br-ovs "table=0, priority=260, in_port=$REP actions=load:$GBP_OPT_OUT->NXM_NX_TUN_GBP_ID[], output:vxlan1"
    ovs-ofctl add-flow br-ovs "table=0, priority=260, in_port=vxlan1, tun_gbp_id=$GBP_OPT_IN actions=output:$REP"
}

function run() {
    # icmp
    ip netns exec ns0 ping -q -c 1 -w 2 $REMOTE
    if [ $? -ne 0 ]; then
        ovs-vsctl show
        err "ping failed"
        return
    fi

    t=15

    ip netns exec ns0 timeout $((t-4)) tcpdump -qnnei $VF -c 30 'tcp' &
    tpid2=$!

    # traffic
    on_remote timeout $((t+2)) iperf3 -s -D

    ip netns exec ns0 timeout $((t+2)) iperf3 -c $REMOTE -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf3 failed"
        return
    fi

    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'tcp' &
    tpid=$!

    sleep $t

    title "Verify traffic on $VF"
    verify_have_traffic $tpid2

    title "Verify no traffic on $REP"
    verify_no_traffic $tpid

    killall -9 -q iperf3
    on_remote killall -9 -q iperf3
    echo "wait for bgs"
    wait
}

config_local
config_remote
sleep 2

run
start_clean_openvswitch
test_done
