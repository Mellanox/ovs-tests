#!/bin/bash
#
# Bug SW #1334271: Syndrome 0xd5ef2 when sending fragmented packets
#
# This verifies there is no duplicate rule syndrome from frag issue
# where mlx5 driver translated frag first/later into frag=yes in HW.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

# we currently don't support offloading of frag first/later
# so testing for offload is disabled.
TEST_OFFLOAD=0

VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"


function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip netns del ns0 &> /dev/null
    ifconfig $VF2 0
}

config_sriov
enable_switchdev
unbind_vfs
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


function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    igmp="01:00:5e:00:00:16"
    RES="ovs_dump_tc_flows | grep 0x0800 | grep -v drop | grep -v $igmp"
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then success; else err; fi
}


ovs-ofctl add-flow brv-1 "in_port($REP),ip,dl_dst=e4:11:11:11:11:11,actions=drop" || err
ovs-ofctl add-flow brv-1 "in_port($REP),ip,icmp,actions=$REP2" || err
ovs-ofctl add-flow brv-1 "in_port($REP2),ip,dl_dst=e4:11:11:11:11:11,actions=drop" || err
ovs-ofctl add-flow brv-1 "in_port($REP2),ip,icmp,actions=$REP" || err


# quick ping to make ovs add rules
ping -q -c 1 -w 1 $VM2_IP -s 2000 && success || err

if [ "$TEST_OFFLOAD" = 1 ]; then
    tdtmpfile=/tmp/$$.pcap
    timeout 15 tcpdump -nnepi $REP icmp -c 30 -w $tdtmpfile &
    tdpid=$!
    sleep 0.5
fi

title "Test ping $VM1_IP -> $VM2_IP - expect to pass"
ping -q -c 30 -i 0.2 -w 15 -s 2000 $VM2_IP && success || err

title "Verify we have 4 rules"
check_offloaded_rules 4

ovs_dump_tc_flows --names
tc -s filter show dev $REP ingress

if [ "$TEST_OFFLOAD" = 1 ]; then
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
fi

rm -fr $tdtmpfile

cleanup
test_done
