#!/bin/bash
#
# This test reproduce an issue we add rule to rhashtable but on error flow didnt
# clean it.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_simple

enable_switchdev_if_no_rep $REP
bind_vfs

function cleanup() {
    ip n d 1.1.1.2 dev $VF lladdr aa:bb:cc:dd:ee:ff &>/dev/null
    reset_tc $REP
    killall iperf &>/dev/null
    killall iperf &>/dev/null
    wait &>/dev/null
}

function test_tc_filter() {
    local a
    local err
    local opnotsupp

    a=`eval tc filter $@ 2>&1`
    err=$?

    echo "$a" | grep -q "Operation not supported" && true || false
    opnotsupp=$?

    if [ $opnotsupp -ne 0 ]; then
        [ -n "$a" ] && echo $a
        fail "Expected operation not supported error"
    fi
}

function test_insert_hw_fail_exists() {
    for i in 1 2 ; do
        test_tc_filter add dev $REP protocol ip parent ffff: prio 1 \
            flower skip_sw dst_mac aa:bb:cc:dd:ee:ff \
            action simple sdata '"unsupported action"'
    done
    success
}

function test_insert_hw_fail_during_traffic() {
    title "test with traffic so we reach tc_classify"

    timeout 6 iperf -c 1.1.1.2 -i 1 -t 5 -u -l 64 -b 1G -P 10 &>/dev/null &

    for i in `seq 10`; do
        tc filter add dev $REP protocol ip parent ffff: prio 1 \
            flower skip_sw dst_mac aa:bb:cc:dd:ee:ff \
            action simple sdata '"unsupported action"' &>/dev/null && fail "expected to fail"
    done

    sleep 6
    killall iperf &>/dev/null
    wait &>/dev/null
    success
}


trap cleanup EXIT

ifconfig $VF 1.1.1.1/24 up
ip n r 1.1.1.2 dev $VF lladdr aa:bb:cc:dd:ee:ff

title "add rule to create flower instance in prio 1 (won't match)"
reset_tc_nic $REP
tc_filter add dev $REP protocol ip parent ffff: prio 1 flower skip_hw dst_mac cc:cc:cc:cc:cc:cc action drop

test_insert_hw_fail_exists
test_insert_hw_fail_during_traffic

test_done
