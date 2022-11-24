#!/bin/bash
#
# Test tc trap with addinital actions (pedit and mirror)
#
# Feature Request #3234990: [BLOOMBERG] Enable additional actions on BF-2 (pedit / mirror)
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function cleanup() {
    ip netns del ns0 2>/dev/null
    ip netns del ns1 2>/dev/null
    reset_tc $REP $REP2
}
trap cleanup EXIT

function config() {
    config_sriov 2
    log "set switchdev"
    config_sriov 3
    enable_switchdev
    bind_vfs
    require_interfaces REP REP2 VF1 VF2
    cleanup

    log "config network"
    ip link set up dev $REP
    ip link set up dev $REP2

    ip netns add ns0
    ip netns add ns1
    ip link set netns ns0 dev $VF1
    ip link set netns ns1 dev $VF2

    ip netns exec ns0 ip link set up dev $VF1
    ip netns exec ns0 ip addr add 7.7.7.7/24 dev $VF1
    ip netns exec ns1 ip link set up dev $VF2
    ip netns exec ns1 ip addr add 7.7.7.8/24 dev $VF2

}

function test_trap_pedit() {
    title "Test tc trap rule with pedit"
    mac0=`ip netns exec ns0 cat /sys/class/net/$VF1/address`
    mac1=`ip netns exec ns1 cat /sys/class/net/$VF2/address`
    mac2="aa:bb:cc:dd:ee:ff"

    reset_tc $REP $REP2
    tc_filter add dev $REP protocol arp prio 1 root flower skip_sw action action mirred egress redirect dev $REP2
    tc_filter add dev $REP2 protocol arp prio 1 root flower skip_sw action action mirred egress redirect dev $REP
    tc_filter add dev $REP protocol ip prio 4 root flower skip_hw dst_mac $mac1 action mirred egress redirect dev $REP2
    tc_filter add dev $REP2 protocol ip prio 4 root flower skip_hw  dst_mac $mac2 action pedit ex munge eth dst set $mac0 pipe action mirred egress redirect dev $REP
    tc_filter add dev $REP2 protocol ip prio 2 root flower skip_sw dst_mac $mac0 action pedit ex munge eth dst set $mac2  pipe action trap

    ip netns exec ns1 ping -c 3 -w 4 7.7.7.7 || fail "Ping failed"

    reset_tc $REP $REP2
}

function test_trap_mirror() {
    title "Test tc trap rule with mirror"
    mac0=`ip netns exec ns0 cat /sys/class/net/$VF1/address`
    mac1=`ip netns exec ns1 cat /sys/class/net/$VF2/address`
    REP3=`get_rep 2`
    VF3=`get_vf 2`
    ip link set dev $REP3 up
    ip link set dev $VF3 up

    reset_tc $REP $REP2
    tc_filter add dev $REP protocol arp prio 1 root flower skip_sw action action mirred egress redirect dev $REP2
    tc_filter add dev $REP2 protocol arp prio 1 root flower skip_sw action action mirred egress redirect dev $REP
    tc_filter add dev $REP protocol ip prio 4 root flower skip_hw dst_mac $mac1 action mirred egress redirect dev $REP2
    tc_filter add dev $REP2 protocol ip prio 4 root flower skip_hw  dst_mac $mac0 action mirred egress redirect dev $REP
    tc_filter add dev $REP2 protocol ip prio 2 root flower skip_sw  dst_mac $mac0 action mirred egress redirect dev $REP3 action trap

    echo "sniff4packets on $VF3"
    timeout 6 tcpdump -qnnei $VF3 -c 3 icmp &
    pid1=$!
    sleep 0.5

    ip netns exec ns1 ping -c 3 -w 4 7.7.7.7 || fail "Ping failed"

    title "test mirror traffic on $VF3"
    verify_have_traffic $pid1

    reset_tc $REP $REP2
}

function test_trap_mirror_pedit() {
    title "Test tc trap rule with mirror and pedit"
    mac0=`ip netns exec ns0 cat /sys/class/net/$VF1/address`
    mac1=`ip netns exec ns1 cat /sys/class/net/$VF2/address`
    mac2="aa:bb:cc:dd:ee:ff"
    REP3=`get_rep 2`
    VF3=`get_vf 2`
    ip link set dev $REP3 up
    ip link set dev $VF3 up

    reset_tc $REP $REP2
    tc_filter add dev $REP protocol arp prio 1 root flower skip_sw action action mirred egress redirect dev $REP2
    tc_filter add dev $REP2 protocol arp prio 1 root flower skip_sw action action mirred egress redirect dev $REP
    tc_filter add dev $REP protocol ip prio 4 root flower skip_hw dst_mac $mac1 action mirred egress redirect dev $REP2
    tc_filter add dev $REP2 protocol ip prio 4 root flower skip_hw  dst_mac $mac2 action pedit ex munge eth dst set $mac0 pipe action mirred egress redirect dev $REP
    tc_filter add dev $REP2 protocol ip prio 2 root flower skip_sw dst_mac $mac0 action mirred egress redirect dev $REP3 action pedit ex munge eth dst set $mac2  pipe action trap

    echo "sniff4packets on $VF3"
    timeout 6 tcpdump -qnnei $VF3 -c 3  ether dst $mac0 &
    pid1=$!
    sleep 0.5

    ip netns exec ns1 ping -c 3 -w 4 7.7.7.7 || fail "Ping failed"

    title "test mirror traffic on $VF3"
    verify_have_traffic $pid1

    reset_tc $REP $REP2
}


config
test_trap_pedit
test_trap_mirror
test_trap_mirror_pedit
trap - EXIT
cleanup
test_done
