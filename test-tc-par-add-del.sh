#!/bin/bash
#
# This verifies that parallel rule insert/delete is handled correctly by tc.
# Tests with large amount of rules updated in batch mode to find any potential
# bugs and race conditions.
#

total=${1:-100000}
skip=$2
rules_per_file=10000

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

echo "setup"
config_sriov 2 $NIC
enable_switchdev_if_no_rep $REP

require_interfaces NIC
reset_tc_nic $NIC

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

    tc_batch $dup "dev $NIC" $total $rules_per_file
    reset_tc_nic $NIC

    echo "Insert rules in parallel"
    ls ${TC_OUT}/add.* | xargs -n 1 -P 100 tc $force -b &>/dev/null
    check_num_rules $max_rules $NIC

    echo "Delete rules in parallel"
    ls ${TC_OUT}/del.* | xargs -n 1 -P 100 tc $force -b &>/dev/null
    check_num_rules 0 $NIC
}

title "Test distinct handles"
par_test 0

title "Test duplicate handles"
par_test 1

test_done
