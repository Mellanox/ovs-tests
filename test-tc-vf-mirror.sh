#!/bin/bash
#
# Test VF Mirror basic VF1->VF2,VF3
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 3
enable_switchdev_if_no_rep $REP
REP3=`get_rep 2`
require_interfaces REP REP2 REP3
unbind_vfs
bind_vfs
VF3=`get_vf 2`
reset_tc $REP
reset_tc $REP2
reset_tc $REP3

mac1=`cat /sys/class/net/$VF/address`
mac2=`cat /sys/class/net/$VF2/address`

test "$mac1" || fail "no mac1"
test "$mac2" || fail "no mac2"

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
}
trap cleanup EXIT

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4

    echo "[$ns] $vf ($ip) -> $rep"
    ifconfig $rep 0 up
    ip netns add $ns
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $ip/24 up
}

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
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol ip prio 2 flower skip_sw \
        dst_mac $mac1 \
        action mirred egress mirror dev $REP3 pipe \
        action mirred egress redirect dev $REP

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress

    echo "sniff packets on $VF3"
    timeout 2 tcpdump -qnei $VF3 -c 6 'icmp' &
    pid=$!

    echo "run traffic"
    ip netns exec ns0 ping -q -c 10 -i 0.1 $IP2

    wait $pid
    # test sniff timedout
    rc=$?
    if [[ $rc -eq 0 ]]; then
        success
    elif [[ $rc -eq 124 ]]; then
        err "No mirrored packets"
    else
        err "Tcpdump failed"
    fi
}


run
test_done
