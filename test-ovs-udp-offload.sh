#!/bin/bash
#
#
#setup:
#       veth0 <-> veth1 <-> OVS <-> veth2 <-> veth3@ns0
#       VM1_IP                                VM2_IP

my_dir="$(dirname "$0")"
. $my_dir/common.sh

test -z "$VF" && fail "Missing VF"
test -z "$VF2" && fail "Missing VF2"
test -z "$REP" && fail "Missing REP"
test -z "$REP2" && fail "Missing REP2"

VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"


function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null
    ifconfig $VF 0
    ifconfig $VF2 0
}

cleanup
enable_switchdev_if_no_rep $REP
bind_vfs

echo "setup ns"
ifconfig $VF2 $VM1_IP/24 up
ip netns add ns0
ip link set $VF netns ns0
ip netns exec ns0 ifconfig $VF $VM2_IP/24 up

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 $REP2


function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    RES="ovs-dpctl dump-flows type=offloaded | grep 'ipv4(proto=17)'"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success; else err; fi
}


ovs-ofctl add-flow brv-1 "in_port($REP),ip,udp,dl_dst=e4:11:11:11:11:11,actions=drop" || err
ovs-ofctl add-flow brv-1 "in_port($REP),ip,udp,actions=$REP2" || err
ovs-ofctl add-flow brv-1 "in_port($REP2),ip,udp,dl_dst=e4:11:11:11:11:11,actions=drop" || err
ovs-ofctl add-flow brv-1 "in_port($REP2),ip,udp,actions=$REP" || err

function quick_udp() {
    title "Test iperf udp $VF($VM1_IP) -> $VF2($VM2_IP)"
    timeout 3 ip netns exec ns0 iperf -u -s &
    iperf -u -c $VM2_IP -t 1 -b1G
    killall -9 iperf
}

# quick traffic to cause offload
quick_udp

tdtmpfile=/tmp/$$.pcap
timeout 15 tcpdump -nnepi $REP udp -c 30 -w $tdtmpfile &
tdpid=$!
sleep 0.5

function test_udp() {
    title "Test iperf udp $VF($VM1_IP) -> $VF2($VM2_IP)"
    timeout 13 ip netns exec ns0 iperf -u -s &
    iperf -u -c $VM2_IP -t 10 -b1G
    killall -9 iperf
}

test_udp
title "Verify we have 2 rules"
check_offloaded_rules 2

ovs-dpctl dump-flows type=offloaded --names
tc -s filter show dev $REP2 ingress

kill $tdpid 2>/dev/null
sleep 1
count=`tcpdump -nr $tdtmpfile | wc -l`
title "Verify with tcpdump"
if [[ $count > 2 ]]; then
    err "No offload"
    tcpdump -nr $tdtmpfile
else
    success
fi

cleanup
test_done
