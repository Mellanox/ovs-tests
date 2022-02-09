#!/bin/bash
#
# Test OVS with 100 different masks
#
# Bug SW #2150295
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

config_sriov 2
enable_switchdev
unbind_vfs
bind_vfs
require_interfaces REP NIC VF


function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
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
    ovs-vsctl add-port br-ovs $NIC
}

function config_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up
               ip a add $REMOTE/24 dev $REMOTE_NIC"
}

function add_openflow_rules() {
    ovs-ofctl add-flow br-ovs "tcp,in_port=$REP,nw_src=$IP,tp_dst=13 action=drop"
    ovs-ofctl add-flow br-ovs "tcp,in_port=$REP,nw_src=$IP,tp_src=13 action=drop"
    ovs-ofctl dump-flows br-ovs --color
}

function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    # make sure we have port masks
    local cmd='ovs_dump_tc_flows | grep -o "eth_type(0x0800).*ipv4(src=.*),tcp(src=[0-9]*/0x.*,dst=[0-9]*/0x.*)"'
    RES=`eval $cmd | wc -l`
    if (( RES == $count )); then success; else err "Expected $count rules but got $RES rules"; fi
}

function run() {
    config
    config_remote
    add_openflow_rules

    echo "Start listeners"
    port=16
    for j in {0..9}; do
        on_remote timeout 10 iperf -s -p $((port)) &> /dev/null &
        let "port=port*2"
    done
    sleep 5

    echo "Start clients"
    cport=16
    for i in {0..9}; do
        port=16
        for j in {0..9}; do
            timeout 2 ip netns exec ns0 iperf -c $REMOTE -t 2 --port $((port)) -B $IP:$((cport+j)) &> /dev/null &
            let "port=port*2"
        done
        let "cport=cport*2"
    done
    sleep 2

    check_offloaded_rules 100

    killall -9 iperf &>/dev/null
    on_remote killall -9 iperf &>/dev/null
    echo "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
