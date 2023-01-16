#!/bin/bash
#
# Test ICMP offload with OVS
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"


function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null
    ifconfig $VF2 0
}

enable_switchdev
unbind_vfs
set_eswitch_inline_mode_transport
bind_vfs
require_interfaces VF VF2 REP REP2
cleanup

echo "setup ns"
ifconfig $VF2 $VM1_IP/24 up
ip netns add ns0
ip link set $VF netns ns0
ip netns exec ns0 ifconfig $VF $VM2_IP/24 up
ifconfig $REP up
ifconfig $REP2 up

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 $REP2

igmp="01:00:5e:00:00:16"

function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    local cmd="ovs_dump_tc_flows | grep 0x0800 | grep -v drop | grep -v $igmp"
    eval $cmd
    RES=`eval $cmd | wc -l`
    if (( RES == $count )); then success; else err; fi

    if eval $cmd | grep "packets:0, bytes:0" ; then
        err "packets:0, bytes:0"
    fi
}


ovs-ofctl add-flow brv-1 "in_port($REP),ip,dl_dst=e4:11:11:11:11:11,actions=drop" || err
ovs-ofctl add-flow brv-1 "in_port($REP),ip,icmp,actions=$REP2" || err
ovs-ofctl add-flow brv-1 "in_port($REP2),ip,dl_dst=e4:11:11:11:11:11,actions=drop" || err
ovs-ofctl add-flow brv-1 "in_port($REP2),ip,icmp,actions=$REP" || err

# quick ping to make ovs add rules
ping -q -c 1 -w 1 $VM2_IP && success || err "ping failed"

tdtmpfile=/tmp/$$.pcap
timeout 7 tcpdump -nnepi $REP icmp -c 30 -w $tdtmpfile &
tdpid=$!
sleep 0.5

title "Test ping $VM1_IP -> $VM2_IP - expect to pass"
ping -q -f -w 7 $VM2_IP && success || err "ping failed"

title "dump"
ovs_dump_tc_flows --names
tc -s filter show dev $REP ingress

title "Test lastused"
for i in `ovs_dump_tc_flows | grep 0x0800 | grep -v $igmp | grep -o "used:[^s,]*" | cut -d: -f2`; do
    if [ "$i" == "never" ]; then
        err "lastuse is never"
        continue
    fi
    # round number down or up.
    c=`printf "%.0f\n" $i`
    if [ $? -ne 0 ]; then
        err "Failed converting used to float"
    fi
    echo "lastused $i -> $c"
    if [ $c -gt 1 ]; then
        err "lastused is $i"
    fi
done

title "Verify we have 2 rules"
check_offloaded_rules 2

kill $tdpid 2>/dev/null
sleep 1
count=`tcpdump -nnr $tdtmpfile | wc -l`
title "Verify with tcpdump"
if [[ $count -gt 2 ]]; then
    err "No offload"
    tcpdump -nnr $tdtmpfile
else
    success
fi

rm -fr $tdtmpfile
cleanup
test_done
