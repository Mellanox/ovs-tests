#!/bin/bash
#
# Bug SW #1659734: [OVS] ignore header rewrite if the new value is the same as the match vlaue
# Bug SW #1623421: [Nuage][OVS] ignore header rewrite if the new value is the same as the match vlaue
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4

VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"
FAKE_VM2_IP="7.7.7.3"

# veth or hw
CASES=${CASES:-"hw"}

function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null

    for i in `seq 0 7`; do
        ip link del veth$i &> /dev/null
    done
}

function check_offloaded_rewrite_rules() {
    local field=$1
    local expected_num_occurrences=$2

    title " - check for $expected_num_occurrences occurrences of \"${field}\" in dp rules"
    RES="ovs_dump_tc_flows | grep 0x0800 | grep -v drop"
    eval $RES
    RES=`eval $RES | grep -o ${field} | wc -l`
    if (( RES == $expected_num_occurrences )); then success
    else
        err "Failed: \"${field}\" occurrences: expected=$expected_num_occurrences, actual=$RES"
    fi
}

function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    RES="ovs_dump_tc_flows | grep 0x0800 | grep -v drop"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success
    else
        ovs_dump_ovs_flows | grep 0x0800 | grep -v drop
        err
    fi
}

function kill_iperf_server() {
    if [ -n "$iperf_server_pid" ]; then
        kill -9 $iperf_server_pid &>/dev/null
        wait $iperf_server_pid &>/dev/null
    fi
}
trap kill_iperf_server EXIT

function test_traffic() {
    local dev=$1
    shift
    local iperf_extra=$@

    timeout -k1 4 iperf -c $FAKE_VM2_IP $iperf_extra -i 999 -t 1 || fail "Iperf failed"

    timeout 2 tcpdump -nnei $dev -c 3 'tcp' &
    tdpid=$!

    timeout -k1 4 iperf -c $FAKE_VM2_IP $iperf_extra -i 999 -t 3 && success || fail "Iperf failed"
    check_offloaded_rules 2

    title "Verify with tcpdump"
    wait $tdpid && err || success

    kill_iperf_server
}

function add_flow() {
    ovs-ofctl add-flow brv-1 $@
}

function test_case() {
    local cs=$1
    local VF=$VF
    local VF2=$VF2
    local REP=$REP
    local REP2=$REP2

    cleanup

    title "Test case $cs"
    start_check_syndrome

    if [[ "$cs" == "veth" ]]; then
        echo "setup veth and ns"
        ip link add veth0 type veth peer name veth1
        ip link add veth2 type veth peer name veth3

        VF=veth1
        VF2=veth3
        REP=veth0
        REP2=veth2
    elif [[ "$cs" == "hw" ]]; then
        enable_switchdev
        unbind_vfs
        bind_vfs
        require_interfaces VF VF2 REP REP2
    else
        fail "Unknown case: $cs"
    fi

    ifconfig $REP up
    ifconfig $VF $VM1_IP/24 up
    ifconfig $REP2 up
    ip netns add ns0
    ip link set $VF2 netns ns0
    ip netns exec ns0 ifconfig $VF2 $VM2_IP/24 up
    ip netns exec ns0 iperf -s -i 999 &
    iperf_server_pid=$!

    echo "setup ovs"
    ovs-vsctl add-br brv-1
    ovs-vsctl add-port brv-1 $REP -- set Interface $REP ofport_request=1
    ovs-vsctl add-port brv-1 $REP2 -- set Interface $REP2 ofport_request=2

    VF_MAC=`cat /sys/class/net/$VF/address`
    VF2_MAC=`ip netns exec ns0 cat /sys/class/net/$VF2/address`

    title "Test $VM1_IP -> fake $FAKE_VM2_IP (will be rewritten to $VM1_IP -> $VM2_IP)"

    ovs-ofctl del-flows brv-1
    add_flow "ip,nw_src=$VM1_IP,nw_dst=$FAKE_VM2_IP,actions=mod_nw_dst=$VM2_IP,normal"
    add_flow "ip,nw_src=$VM2_IP,nw_dst=$VM1_IP,actions=mod_nw_src=$FAKE_VM2_IP,normal"
    add_flow "arp,actions=normal"

    ip n replace $FAKE_VM2_IP dev $VF lladdr $VF2_MAC
    ip netns exec ns0 ip n replace $FAKE_VM1_IP dev $VF2 lladdr $VF_MAC

    test_traffic $REP
    check_offloaded_rewrite_rules $VM1_IP 2

    start_clean_openvswitch

    check_syndrome
}

for cs in $CASES; do
    test_case $cs
done

cleanup
test_done
