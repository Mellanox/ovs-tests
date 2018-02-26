#!/bin/bash
#
# Bug SW #1315045: Overlapping rules with fragmented traffic
#
#setup:
#       veth0 <-> veth1 <-> OVS <-> veth2 <-> veth3@ns0
#       VM1_IP                                VM2_IP

my_dir="$(dirname "$0")"
. $my_dir/common.sh

VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"

# if we want to test veth
TEST_VETH=${TEST_VETH:-0}

if [[ "$TEST_VETH" == 1 ]]; then
    VF=veth0
    REP=veth1
    VF2=veth2
    REP2=veth3
fi


function clean_veth() {
    ip link del veth0 2>/dev/null
    ip link del veth1 2>/dev/null
    ip link del veth2 2>/dev/null
    ip link del veth3 2>/dev/null
}

function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null
    ifconfig $VF 0 &> /dev/null
    ifconfig $VF2 0 &> /dev/null
    clean_veth
}

trap clean_veth EXIT
cleanup

if [[ "$TEST_VETH" == 1 ]]; then
    ip link add veth0 type veth peer name veth1
    ip link add veth2 type veth peer name veth3

    ifconfig veth0 up
    ifconfig veth1 up
    ifconfig veth2 up
    ifconfig veth3 up
else
    enable_switchdev_if_no_rep $REP
    bind_vfs
fi

echo "setup ns"
ifconfig $VF2 $VM1_IP/24 up
ip netns add ns0
ip link set $VF netns ns0
ip netns exec ns0 ifconfig $VF $VM2_IP/24 up

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 $REP2


function check_rules() {
    local count=$1
    title "Verify $count rules"
    TMP=/tmp/dump-$$
    ovs-dpctl dump-flows --names | grep 'ipv4(proto=17' > $TMP
    cat $TMP
    RES=`cat $TMP | wc -l`
    if (( RES == $count )); then success; else err; fi
}

function err_clean() {
    cleanup
    fail
}


ovs-ofctl add-flow brv-1 "priority=9999,dl_dst=11:11:11:11:11:11,actions=drop" || err_clean
ovs-ofctl add-flow brv-1 "priority=100,udp,tp_dst:5002 actions=drop" || err_clean

function test_udp() {
    title "Test iperf udp $VF($VM1_IP) -> $VF2($VM2_IP)"
    iperf -u -c $VM2_IP -t 1 -P1 -l 1550
}

# TODO verify we actually run iperf with mtu > netdev mtu
test_udp
check_rules 2

if [[ "$TEST_VETH" == 1 ]]; then
    in_port=veth3
    actions=veth1
else
    in_port=$REP2
    actions=$REP
fi

title "Verify no overlap rules"
# TMP created in check_rules()
count=`cat $TMP | grep "in_port($in_port)" | grep "actions:$actions" | grep "eth_type(0x0800)" | grep "ipv4(proto=17)" | wc -l`
if [[ $count -gt 1 ]]; then
    err "Detected overlap rules"
else
    success
fi

cleanup
test_done
