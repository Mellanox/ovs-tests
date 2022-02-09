#!/bin/bash
#
# Test TCP offload with OVS
#
#setup:
#       veth0 <-> veth1 <-> OVS <-> veth2 <-> veth3@ns0
#       VM1_IP                                VM2_IP

my_dir="$(dirname "$0")"
. $my_dir/common.sh

VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"


function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null
    ifconfig $VF 0
}

enable_switchdev
unbind_vfs
set_eswitch_inline_mode_transport
bind_vfs
require_interfaces VF VF2 REP REP2
cleanup

echo "setup ns"
ifconfig $VF $VM1_IP/24 up
ip netns add ns0
ip link set $VF2 netns ns0
ip netns exec ns0 ifconfig $VF2 $VM2_IP/24 up
ifconfig $REP up
ifconfig $REP2 up

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 $REP2


function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    local cmd="ovs_dump_tc_flows | grep ipv4 | grep proto=6 | grep -v drop"
    eval $cmd
    RES=`eval $cmd | wc -l`
    if (( RES == $count )); then success; else err; fi

    if eval $cmd | grep "packets:0, bytes:0" ; then
        err "packets:0, bytes:0"
    fi
}


ovs-ofctl add-flow brv-1 "in_port($REP),ip,tcp,dl_dst=e4:11:11:11:11:11,actions=drop" || err
ovs-ofctl add-flow brv-1 "in_port($REP),ip,tcp,actions=$REP2" || err
ovs-ofctl add-flow brv-1 "in_port($REP2),ip,tcp,dl_dst=e4:11:11:11:11:11,actions=drop" || err
ovs-ofctl add-flow brv-1 "in_port($REP2),ip,tcp,actions=$REP" || err

function quick_tcp() {
    title "Test iperf tcp $VF($VM1_IP) -> $VF2($VM2_IP)"
    timeout 3 ip netns exec ns0 iperf -s &
    sleep 0.5
    iperf -c $VM2_IP -t 1
    killall -9 iperf
    wait &>/dev/null
}

# quick traffic to cause offload
quick_tcp

tdtmpfile=/tmp/$$.pcap
timeout 15 tcpdump -nnepi $REP tcp -c 30 -w $tdtmpfile &
tdpid=$!
sleep 0.5

function test_tcp() {
    title "Test iperf tcp $VF($VM1_IP) -> $VF2($VM2_IP)"
    timeout 13 ip netns exec ns0 iperf -s &
    sleep 0.5
    iperf -c $VM2_IP -t 12
    killall -9 iperf
    wait &>/dev/null
}

test_tcp
title "Verify we have 2 rules"
check_offloaded_rules 2

ovs_dump_tc_flows --names
tc -s filter show dev $REP ingress

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

rm -fr $tdtmpfile
cleanup
test_done
