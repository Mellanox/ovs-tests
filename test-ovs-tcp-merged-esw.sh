#!/bin/bash
#
# Test traffic with merged esw configuration

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function cleanup() {
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null
    ip netns del ns1 &> /dev/null
    config_sriov 0 $NIC2
}

trap cleanup EXIT
cleanup

config_sriov 2
config_sriov 2 $NIC2
enable_switchdev $NIC
enable_switchdev $NIC2
unbind_vfs
unbind_vfs $NIC2
bind_vfs
bind_vfs $NIC2
VF2=`get_vf 0 $NIC2`
REP2=`get_rep 0 $NIC2`
require_interfaces REP REP2 VF VF2
VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"

echo "setup ns"
config_vf ns0 $VF $REP $VM1_IP
config_vf ns1 $VF2 $REP2 $VM2_IP

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 $REP2


function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    local cmd="ovs_dump_tc_flows | grep 0x0800 | grep -v drop"
    eval $cmd
    RES=`eval $cmd | wc -l`
    if (( RES == $count )); then success; else err; fi

    if eval $cmd | grep "packets:0, bytes:0" ; then
        err "packets:0, bytes:0"
    fi
}

function quick_tcp() {
    title "Test iperf tcp $VF($VM1_IP) -> $VF2($VM2_IP)"
    timeout 4 ip netns exec ns1 iperf -s &
    sleep 2
    ip netns exec ns0 iperf -c $VM2_IP -t 1
    killall -9 iperf
    wait &>/dev/null
}

ip netns exec ns0 ping -c 1 -w 4 -q $VM2_IP || err "Ping failed"
fail_if_err

# quick traffic to cause offload
quick_tcp

tdtmpfile=/tmp/$$.pcap
timeout 16 tcpdump -nnepi $REP tcp -c 30 -w $tdtmpfile &
tdpid=$!
sleep 1

function test_tcp() {
    title "Test iperf tcp $VF($VM1_IP) -> $VF2($VM2_IP)"
    timeout 15 ip netns exec ns1 iperf -s &
    sleep 2
    ip netns exec ns0 iperf -c $VM2_IP -t 12
    killall -9 iperf
    wait &>/dev/null
}

test_tcp
title "Verify we have 2 rules"
check_offloaded_rules 2

kill $tdpid 2>/dev/null
sleep 1
count=`tcpdump -nnr $tdtmpfile | wc -l`
title "Verify with tcpdump"
if [[ $count -gt 2 ]]; then
    err "No offload"
    tcpdump -nner $tdtmpfile
else
    success
fi

echo "cleanup"
rm -fr $tdtmpfile
cleanup
trap - EXIT
test_done
