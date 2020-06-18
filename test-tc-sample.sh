#!/bin/bash
#
# Test act_sample action.
#
# act_sample uses psample kernel module. In order to verify the test result,
# introduce a program 'psample' to verify it.
# 'psample' can print input ifindex, sample rate, trunc size, sequence number
# and the packet content.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

psample_dir=$my_dir/psample

require_module act_sample psample

test -x $psample_dir/psample || make -C $psample_dir || \
    fail "failed to compile psample in dir $psample_dir"

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 2
enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP $REP2

mac1=$(cat /sys/class/net/$VF/address)
mac2=$(cat /sys/class/net/$VF2/address)

test "$mac1" || fail "no mac1"
test "$mac2" || fail "no mac2"

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP $REP2
}
trap cleanup EXIT

function run() {
    skip=$2
    reset_tc $REP $REP2
    title $1
    local n=10
    local file=/tmp/psample.txt

    local group=5
    local rate=1
    local trunc=96
    local iifindex=$(cat /sys/class/net/$REP/ifindex)

    echo "add arp rules"
    tc_filter add dev $REP ingress protocol arp prio 1 flower \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol arp prio 1 flower \
        action mirred egress redirect dev $REP

    echo "add vf sample rules"
    tc_filter add dev $REP ingress protocol ip prio 2 flower $skip \
        dst_mac $mac2 \
        action sample rate $rate group $group trunc $trunc \
        action mirred egress redirect dev $REP2

    tc_filter add dev $REP2 ingress protocol ip prio 2 flower $skip \
        dst_mac $mac1 \
        action mirred egress redirect dev $REP

    fail_if_err

    ip link show dev $REP
    tc filter show dev $REP ingress

    pkill psample
    timeout 2 $psample_dir/psample -n $n > $file &
    pid=$!

    title "run traffic"
    ip netns exec ns0 ping -q -c $n -i 0.1 -w 2 $IP2 || err "Ping failed"

    fail_if_err
    wait $pid

    title "verify sample"
    psample_iifindex=$(awk '/iifindex/{print $2}' $file | head -1)
    if (( $iifindex == $psample_iifindex )); then
        success2 "get correct sample iifindex $psample_iifindex"
    else
        err "get wrong sample iifindex $psample_iifindex"
    fi

    psample_rate=$(awk '/rate/{print $2}' $file | head -1)
    if (( $rate == $psample_rate )); then
        success2 "get correct sample rate $psample_rate"
    else
        err "get wrong sample rate $psample_rate"
    fi

    psample_group=$(awk '/group/{print $2}' $file | head -1)
    if (( $group == $psample_group )); then
        success2 "get correct sample group $psample_group"
    else
        err "get wrong sample group $psample_group"
    fi

    psample_trunc=$(awk '/trunc/{print $2}' $file | head -1)
    if (( $trunc == $psample_trunc )); then
        success2 "get correct sample trunc $psample_trunc"
    else
        err "get wrong sample trunc $psample_trunc"
    fi

    psample_seq=$(grep -c seq $file)
    if (( $n == $psample_seq )); then
        success2 "get correct sample seq $psample_seq"
    else
        err "get wrong sample seq $psample_seq"
    fi
}

config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2

run "Test act_sample action with skip_hw" skip_hw

test_done
