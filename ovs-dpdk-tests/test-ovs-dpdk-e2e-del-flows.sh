#!/bin/bash
#
# Test OVS-DPDK E2E-CACHE flow deletion
#
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

IP=1.1.1.7
IP2=1.1.1.8

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    cleanup_e2e_cache
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    enable_e2e_cache
    echo "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $IP
    config_ns ns1 $VF2 $IP2
}

function add_openflow_rules1() {
    ovs-ofctl del-flows br-phy
    ovs-ofctl add-flow br-phy "arp,actions=NORMAL"
    ovs-ofctl add-flow br-phy "table=0,tcp,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow br-phy "table=1,tcp,ct_state=+trk+new,actions=ct(zone=5, commit),NORMAL"
    ovs-ofctl add-flow br-phy "table=1,tcp,ct_state=+trk+est,ct_zone=5,actions=normal"
    echo -e "\nOVS flow rules:"
    ovs-ofctl dump-flows br-phy --color
}

function del_openflow_rules() {
    ovs-ofctl del-flows br-phy
    echo -e "\nOVS deleted flows rules:"
    ovs-ofctl dump-flows br-phy --color
}

function run() {
    config
    add_openflow_rules1

    echo -e "\nTesting TCP traffic"
    t=2
    # traffic
    ip netns exec ns0 iperf -s &
    pid1=$!
    sleep 2
    ip netns exec ns1 iperf -c $IP -t $((t+2)) -P 10 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    kill -9 $pid1 &>/dev/null
    killall iperf &>/dev/null
    echo "wait for bgs"
    wait

    # check number of flows
    x=$(ovs-appctl dpctl/dump-e2e-flows |wc -l)
    echo "Number of merged flows: ";echo $x

    del_openflow_rules
    y=$(ovs-appctl dpctl/dump-e2e-flows |wc -l)
    echo "Number of merged flows after deletion: ";echo $y
    if [ $y -ne 0 ]; then
        err "Flows not deleted"
    fi

}

run
start_clean_openvswitch
test_done
