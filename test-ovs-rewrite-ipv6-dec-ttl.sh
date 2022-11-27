#!/bin/bash
#
# Test OVS rewrite of IPv6 TTL
#
# [Kernel Upstream] Bug SW #2583765: [Upstream, ASAP, IPv6] Traffic not pass with decrement TTL rule
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

min_nic_cx6dx

VF1_IP="2001:0db8:0:f101::1"
VF2_IP="2001:0db8:0:f101::2"

function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null
    ip netns del ns1 &> /dev/null
}

function setup() {
    title "setup"
    config_sriov
    enable_switchdev
    unbind_vfs
    bind_vfs
    require_interfaces VF VF2 REP REP2

    local mac1=`cat /sys/class/net/$VF/address`
    local mac2=`cat /sys/class/net/$VF2/address`

    config_vf ns0 $VF $REP $VF1_IP
    config_vf ns1 $VF2 $REP2 $VF2_IP
    ip -6 -netns ns0 neigh replace $VF2_IP dev $VF lladdr $mac2
    ip -6 -netns ns1 neigh replace $VF1_IP dev $VF2 lladdr $mac1
    ovs-vsctl add-br ovs-sriov1
    ovs-vsctl add-port ovs-sriov1 $REP
    ovs-vsctl add-port ovs-sriov1 $REP2
}

function check_offloaded_rules() {
    title "Verify for offloaded rule"
    RES="ovs_dump_tc_flows | grep -i 0x86DD | grep 'proto=6' | grep -v drop"
    eval $RES
    RES=$(eval $RES | wc -l)
    if (( RES == 2 )); then
        success
    else
        ovs_dump_ovs_flows | grep -i 0x86DD | grep 'proto=6' | grep -v drop
        err
    fi
}

function test_case_ttl() {
    title "Test IPv6 ttl rewrite"

    ovs-ofctl del-flows ovs-sriov1 ip

    ovs-ofctl add-flow ovs-sriov1 "ipv6,in_port=$REP,action=dec_ttl,output:$REP2"
    ovs-ofctl add-flow ovs-sriov1 "ipv6,in_port=$REP2,action=dec_ttl,output:$REP"

    t=15
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+7)) iperf -s --ipv6_domain >/dev/null &
    sleep 2
    ip netns exec ns0 timeout $((t+2)) iperf --ipv6_domain -t $t -c $VF2_IP -P 3 -i 1 >/dev/null &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 10 'tcp' &
    local pid=$!

    title "Verify rewrite value"
    rm -f /tmp/dump
    timeout 2 ip netns exec ns1 tcpdump -vvi $VF2 -c 1 'tcp' -Q in -w /tmp/dump
    local pid2=$!

    check_offloaded_rules

    title "Verify no traffic on $REP"
    verify_no_traffic $pid

    title "Verify ttl value"
    wait $pid2
    tcpdump -vvr /tmp/dump | grep "hlim 63" && success || err "Wrong ttl value"

    pkill -9 iperf &>/dev/null
    wait &>/dev/null
}

cleanup
setup
test_case_ttl
cleanup
test_done
