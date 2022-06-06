#!/bin/bash
#
# Test OVS with vxlan traffic
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
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789
}

function add_openflow_rules() {
#    ovs-ofctl del-flows br-ovs
#    ovs-ofctl add-flow br-ovs arp,actions=normal
#    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    config
    config_remote_vxlan
    add_openflow_rules
    sleep 2

    # icmp
    ip netns exec ns0 ping -q -c 1 -w 2 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    t=15

    ip netns exec ns0 timeout $((t-4)) tcpdump -qnnei $VF -c 30 'tcp' &
    tpid2=$!

    # traffic
    on_remote timeout $((t+2)) iperf -s -t $t &
    pid1=$!
    sleep 2
    ip netns exec ns0 timeout $((t+2)) iperf -c $REMOTE -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'tcp' &
    tpid=$!

    sleep $t

    title "Verify traffic on $VF"
    verify_have_traffic $tpid2

    title "Verify no traffic on $REP"
    verify_no_traffic $tpid

    kill -9 $pid1 &>/dev/null
    killall iperf &>/dev/null
    echo "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
