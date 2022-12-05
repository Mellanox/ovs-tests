#!/bin/bash
#
# Test VF Mirror basic VF1->VF2,VF3 with mirrors on same and different nics
#
# Bug SW #1718378: [upstream] syndrome (0x563e2f) followed by kernel panic during VF mirroring under stress traffic.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

require_interfaces NIC NIC2
config_sriov 3
config_sriov 1 $NIC2
enable_switchdev
enable_switchdev $NIC2
REP3=`get_rep 2`
REP4=`get_rep 0 $NIC2`
require_interfaces REP REP2 REP3 REP4
unbind_vfs
unbind_vfs $NIC2
bind_vfs
bind_vfs $NIC2
VF3=`get_vf 2`
VF4=`get_vf 0 $NIC2`
require_interfaces VF VF2 VF3 VF4

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
    title $1
    local vf_mirror=$2
    local mirror=$3

    ifconfig $vf_mirror 0 up
    ifconfig $mirror 0 up
    reset_tc $REP $REP2

    title "add arp rules"
    tc_filter add dev $REP ingress protocol arp prio 1 flower \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol arp prio 1 flower \
        action mirred egress redirect dev $REP

    title "add vf mirror rules"
    tc_filter add dev $REP ingress protocol ip prio 2 flower skip_sw \
        dst_mac $mac2 \
        action mirred egress mirror dev $mirror pipe \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol ip prio 2 flower skip_sw \
        dst_mac $mac1 \
        action mirred egress mirror dev $mirror pipe \
        action mirred egress redirect dev $REP

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress

    title "sniff packets on $vf_mirror"
    timeout 5 tcpdump -qnei $vf_mirror -c 6 "icmp[icmptype] == icmp-echo" &
    pid1=$!
    timeout 5 tcpdump -qnei $vf_mirror -c 6 "icmp[icmptype] == icmp-echoreply" &
    pid2=$!

    title "run traffic"
    ip netns exec ns0 ping -q -i 0.2 -w 5 $IP2 || err "Ping failed"

    title "verify mirred packets - echo req"
    verify_have_traffic $pid1
    title "verify mirred packets - echo reply"
    verify_have_traffic $pid2
}

config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2

run "Test VF mirror, with mirror on same nic" $VF3 $REP3
fail_if_err
run "Test VF mirror, with mirror on different nic" $VF4 $REP4

# back to defaults
trap - EXIT
cleanup
config_sriov 0 $NIC2
test_done
