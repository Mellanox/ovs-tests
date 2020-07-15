#!/bin/bash
#
# This verifies that parallel rule insertion doesn't cause for duplicate rules
# Bug SW #1598025: Duplicate rules when running udp traffic
#

total=${1:-1000}
rules_per_file=20

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

echo "setup"
config_sriov 2 $NIC
enable_switchdev

require_interfaces NIC
reset_tc $NIC

function test_dup() {
    g="dst_mac e4:12:00:00:"
    a=`cat $dump | grep "$g"`
    if [ -z "$a" ]; then
        err "Didn't find any rules. please check."
        return
    fi

    a=`cat $dump | grep "$g" | sort | uniq -d`
    if [ -n "$a" ]; then
        err "Found duplicated rules"
        echo "for example:"
        cat $dump | grep "$g" | sort | uniq -d | tail -5
    fi
}

function run() {
    local dup=0
    local force='-force'
    local max_rules=$total
    local dump=/tmp/dump-$$

    echo "Generating distinct batches"

    no_handle=1
    tc_batch $dup "dev $NIC" $total $rules_per_file
    reset_tc $NIC

    echo "Insert rules in parallel"
    for i in `seq 10`; do
        ls ${TC_OUT}/add.* | xargs -n 1 -P 100 tc $force -b &>/dev/null &
    done

    wait

    tc filter show dev $NIC ingress > $dump
    test_dup

    ls ${TC_OUT}/del.* | xargs -n 1 -P 100 tc $force -b &>/dev/null
}

title "Test for duplicate rules in parallel insertion"
run

test_done
