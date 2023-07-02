#!/bin/bash
#
# Test OVS with vxlan traffic with tos and ecn bits changing by kernel vxlan driver before matching in tc
#
# Require external server
#
# Bug SW #2687643: [NGN] RoCE traffic is not offloaded with OVS ToS inherit + Geneve tunneling
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    ovs_clear_bridges
    reset_tc $REP
    cleanup_remote_vxlan
    for d in vxlan1 $REMOTE_NIC; do
        on_remote tc qdisc del dev $d clsact &>/dev/null
    done
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    ifconfig $NIC $LOCAL_TUN/24 up
    # WA SimX bug? interface not receiving traffic from tap device to down&up to fix it.
    for i in $NIC $VF $REP ; do
            ifconfig $i down
            ifconfig $i up
            reset_tc $i
    done
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP/24 up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789 options:csum=true

    ovs-ofctl del-flows br-ovs
    for i in `seq 0 3`; do
        ovs-ofctl add-flow br-ovs "ip,ip_ecn=$i,actions=normal"
    done
    ovs-ofctl add-flow br-ovs "arp,actions=normal"
}

function config_remote_tc_tos() {
    for d in vxlan1 $REMOTE_NIC; do
        on_remote tc qdisc del dev $d ingress &>/dev/null
        on_remote tc qdisc del dev $d clsact &>/dev/null
        on_remote tc qdisc add dev $d clsact
    done

    on_remote tc filter add dev $REMOTE_NIC egress proto ip flower skip_hw action pedit munge ip tos set 1 pipe action csum ip tcp
    on_remote tc filter add dev vxlan1 egress proto ip flower skip_hw action pedit munge ip tos set 2 pipe action csum ip tcp
}

function run() {
    local offloaded=false

    config
    config_remote_vxlan
    config_remote_tc_tos
    sleep 2

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

    sleep $((t-5))
    ovs-appctl dpctl/dump-flows -m | grep "in_port(vxl" | grep 0800
    ovs-appctl dpctl/dump-flows -m | grep 'in_port(vxl' | grep 'offloaded:yes' | grep '0800' && offloaded=true
    sleep 5

    title "Verify traffic on $VF"
    verify_have_traffic $tpid2

    if $offloaded; then
        title "Tunnel rule offloaded, verify no traffic on $REP"
        verify_no_traffic $tpid
    else
        title "Tunnel rule not-offloaded, verify traffic on $REP"
        verify_have_traffic $tpid
    fi

    killall -9 -q iperf3
    on_remote killall -9 -q iperf3
    echo "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
