#!/bin/bash
#
# Test ICMP traffic when reps configured with 4 combined channels
# check there are no duplicate packets.
#
# Bug SW #1628953: [jd] packet sent out from VF are duplicated with latest FW
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
    ethtool -L $REP combined 1
    ethtool -L $REP2 combined 1
}
trap cleanup EXIT

function run() {
    title "Test ICMP with 4 rx channels"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    ethtool -L $REP combined 4
    ethtool -L $REP2 combined 4

    # issue hapens when not offloaded to hw
    skip=skip_hw

    echo "add arp rules"
    tc_filter add dev $REP ingress protocol arp prio 1 flower $skip \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol arp prio 1 flower $skip \
        action mirred egress redirect dev $REP

    echo "add ip rules"
    tc_filter add dev $REP ingress protocol ip prio 2 flower $skip \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol ip prio 2 flower $skip \
        action mirred egress redirect dev $REP

    fail_if_err

    echo "sniff packets on $VF"
    timeout 2 ip netns exec ns0 tcpdump -qnnei $VF -c 10 'icmp' &
    pid=$!
    timeout 2 ip netns exec ns0 tcpdump -qnnei $VF -c 4 'icmp[6:2] == 2' &>/dev/null &
    pid2=$!

    sleep 0.5

    echo "run traffic"
    ip netns exec ns0 ping -q -c 10 -i 0.1 -w 2 $IP2 || err "Ping failed"

    title "Verify traffic on $VF"
    verify_have_traffic $pid
    Title "Verify no duplicate packets on $VF"
    verify_no_traffic $pid2
}


start_check_syndrome
run
check_syndrome
test_done
