#!/bin/bash
#
# Test VF Mirror with pedit VF1->VF2,pedit,VF3
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 3
enable_switchdev
REP3=`get_rep 2`
require_interfaces REP REP2 REP3
unbind_vfs
bind_vfs
VF3=`get_vf 2`
reset_tc $REP $REP2

mac1=`cat /sys/class/net/$VF/address`
mac2=`cat /sys/class/net/$VF2/address`

test "$mac1" || fail "no mac1"
test "$mac2" || fail "no mac2"

function cleanup() {
    ip netns del ns0
    ip netns del ns1
    reset_tc $REP $REP2
}
trap cleanup EXIT

function run() {
    title "Test VF Mirror"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    ifconfig $VF3 0 up
    ifconfig $REP3 0 up

    echo "add arp rules"
    tc_filter add dev $REP ingress protocol arp prio 1 flower \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol arp prio 1 flower \
        action mirred egress redirect dev $REP

    echo "add vf mirror rules"
    tc_filter add dev $REP ingress protocol ip prio 2 flower skip_sw \
        dst_mac $mac2 \
        action mirred egress mirror dev $REP3 pipe \
        action pedit ex munge eth src set 20:22:33:44:55:66 pipe \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol ip prio 2 flower skip_sw \
        dst_mac $mac1 \
        action mirred egress mirror dev $REP3 pipe \
        action mirred egress redirect dev $REP

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress

    echo "sniff packets on $VF3"
    timeout 2 tcpdump -qnei $VF3 -c 6 "icmp[icmptype] == icmp-echo" &
    pid1=$!
    timeout 2 tcpdump -qnei $VF3 -c 6 "icmp[icmptype] == icmp-echoreply" &
    pid2=$!

    echo "run traffic"
    ip netns exec ns0 ping -q -c 10 -i 0.1 -w 2 $IP2 || err "Ping failed"

    title "verify mirred packets - echo req"
    verify_have_traffic $pid1
    title "verify mirred packets - echo reply"
    verify_have_traffic $pid2
}


run
trap - EXIT
cleanup
test_done
