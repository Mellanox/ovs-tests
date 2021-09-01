#!/bin/bash
#
# This test reproduce an issue we add rule to rhashtable but on error flow didnt
# clean it.
#
# Bug SW #1658428: [upstream] On error flow from HW and skip_sw, we forgot to remove the rhashtable entry

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev
bind_vfs

function stop_iperf() {
    killall -9 iperf &>/dev/null
    wait &>/dev/null
}

function cleanup() {
    ip n d 1.1.1.2 dev $VF lladdr aa:bb:cc:dd:ee:ff &>/dev/null
    reset_tc $REP
    stop_iperf
}

function test_tc_filter() {
    local a
    local err
    local fwddrop

    a=`eval tc filter $@ 2>&1`
    err=$?

    # Also match for "Invalid argument" to preserve compatibility with old kernels
    echo "$a" | grep -q "Rule must have at least one forward/drop action\|Invalid argument" && true || false
    fwddrop=$?

    if [ $fwddrop -ne 0 ]; then
        [ -n "$a" ] && echo $a
        fail "Expected mlx5-specific error message that requires at least one forward/drop action when offloading rule"
    fi
}

function test_insert_hw_fail_exists() {
    for i in 1 2 ; do
        test_tc_filter $tc_command
    done
    success
}

function test_insert_hw_fail_during_traffic() {
    title "test with traffic so we reach tc_classify"

    timeout 6 iperf -c 1.1.1.2 -i 1 -t 5 -u -l 64 -b 1G -P 10 &>/dev/null &

    for i in `seq 10`; do
        tc filter $tc_command &>/dev/null && fail "expected to fail"
    done

    sleep 6
    stop_iperf
    success
}


trap cleanup EXIT
tc_test_verbose
tc_command="add dev $REP protocol ip parent ffff: prio 1 \
            flower $tc_verbose skip_sw dst_mac aa:bb:cc:dd:ee:ff \
            action tunnel_key unset"

ifconfig $VF 1.1.1.1/24 up
ip n r 1.1.1.2 dev $VF lladdr aa:bb:cc:dd:ee:ff

title "add rule to create flower instance in prio 1 (won't match)"
reset_tc $REP
tc_filter add dev $REP protocol ip parent ffff: prio 1 flower skip_hw dst_mac cc:cc:cc:cc:cc:cc action drop

test_insert_hw_fail_exists
test_insert_hw_fail_during_traffic

test_done
