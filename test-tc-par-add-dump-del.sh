#!/bin/bash
#
# This verifies that parallel rule insert/delete/dump is handled correctly by tc.
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

function par_test() {
    local dup=$1
    local force=''
    local max_rules=$total
    if [ $dup == 1 ]; then
        max_rules=`min $total $rules_per_file`
        echo "Generating duplicate batches"
        force='-force'
    else
        echo "Generating distinct batches"
    fi

    skip=skip_sw
    action="mirred egress redirect dev $REP"
    tc_batch $dup "dev $NIC" $total $rules_per_file
    reset_tc $NIC

    tmpflush=/tmp/flush-$$
    rm -f $tmpflush
    touch $tmpflush
    for i in `seq $total`; do
        tc -s filter show dev $NIC ingress >> $tmpflush
    done

    echo "Insert/Dump/Delete rules in parallel"
    for i in `seq 10`; do
        ls ${TC_OUT}/add.* | xargs -n 1 -P 100 tc $force -b &>/dev/null &
        tc $force -b $tmpflush &>/dev/null &
        ls ${TC_OUT}/del.* | xargs -n 1 -P 100 tc $force -b &>/dev/null &
    done

    wait
    ls ${TC_OUT}/del.* | xargs -n 1 -P 100 tc $force -b &>/dev/null
}

title "Test distinct handles"
par_test 0

test_done
