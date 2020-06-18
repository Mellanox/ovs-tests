#!/bin/bash
#
# Test OVS rewrite of DSCP part of ToS field
#
# Feature #1920185: [Design] - [Meituan] LAG: Offloading does not work for action 'mod_nw_tos' on CentOS 7.4/OFED 4.6 on ConnectX-5
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4

VF1_IP="7.7.7.1"
VF2_IP="7.7.7.2"

function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null
    ip netns del ns1 &> /dev/null
}

function create_namespace() {
    local ns=$1
    local rep=$2
    local vf=$3
    local addr=$4

    ifconfig $rep up
    ip netns add $ns
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $addr/24 up
    echo "Create namespace $ns: $rep ($vf) -> $addr/24"
}

function setup() {
    title "- setup"
    config_sriov
    enable_switchdev
    unbind_vfs
    bind_vfs
    require_interfaces VF VF2 REP REP2
    create_namespace ns0 $REP $VF $VF1_IP
    create_namespace ns1 $REP2 $VF2 $VF2_IP
    ovs-vsctl add-br ovs-sriov1
    ovs-vsctl add-port ovs-sriov1 $REP
    ovs-vsctl add-port ovs-sriov1 $REP2
}

function check_offloaded_rules() {
    title " - check for offloaded rule"
    RES="ovs_dump_tc_flows | grep 0x0800 | grep -v drop"
    eval $RES
    RES=$(eval $RES | wc -l)
    if (( RES == 2 ));then success
    else
        ovs_dump_ovs_flows | grep 0x0800 | grep -v drop
        err
    fi
}

function test_case_dscp() {
    title "Test ToS(DSCP) rewrite"

    ovs-ofctl del-flows ovs-sriov1 ip
    start_check_syndrome

    ovs-ofctl add-flow ovs-sriov1 "ip,in_port=$REP,action=mod_nw_tos:68,output:$REP2"

    timeout 3 tcpdump -nnei $REP -c 3 'icmp' 2>/dev/null >/dev/null &
    pid=$!

    title "Verify rewrite value"
    timeout 2 ip netns exec ns1 tcpdump -vvi $VF2 -c 1 'icmp' | \
        grep 0x44 >/dev/null && success || err &

    echo traffic
    ip netns exec  ns0 ping -I $VF $VF2_IP -c 5 -i 0.2 -q

    check_offloaded_rules
    title "Verify offload"
    wait $pid && err || success

    check_syndrome
}

cleanup
setup
test_case_dscp
cleanup
test_done