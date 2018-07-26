#!/bin/bash
#
# This test verifies re-offload functionality when block that already has
# offloaded rules is attached to another qdisc. Expected behavior is that all
# existing rules are re-offloaded to new device and any new rules are offloaded
# to both devices.
#


total=${1:-5000}
rules_per_file=1000

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

echo "setup"
config_sriov 2 $NIC
enable_switchdev_if_no_rep $REP
config_sriov 2 $NIC2
enable_switchdev_if_no_rep $REP2

require_interfaces NIC NIC2 REP REP2
reset_tc_nic $NIC
reset_tc_nic $NIC2
reset_tc_nic $REP
reset_tc_nic $REP2

echo "Clean tc rules"
tc qdisc del dev $REP ingress > /dev/null 2>&1
tc qdisc del dev $REP2 ingress > /dev/null 2>&1

function par_test() {
    local del=$1
    local max_rules=$total

    ! tc qdisc del dev $REP ingress_block 1 ingress > /dev/null 2>&1
    ! tc qdisc del dev $REP2 ingress_block 1 ingress> /dev/null 2>&1
    tc qdisc add dev $REP ingress_block 1 ingress

    echo "Insert rules"
    tc -b ${TC_OUT}/add.0 &>/dev/null
    check_num_offloaded_rules $rules_per_file 1 1

    tc qdisc add dev $REP2 ingress_block 1 ingress &>/dev/null &

    if [ $del == 0 ]; then
        echo "Add rules in parallel"
        ls ${TC_OUT}/add.* | xargs -n 1 -P 100 tc -b &>/dev/null
        wait
        check_num_offloaded_rules $max_rules 2 1
    else
        echo "Delete rules in parallel"
        ls ${TC_OUT}/del.* | xargs -n 1 -P 100 tc -b &>/dev/null
        wait
        check_num_offloaded_rules 0 2 1
    fi

    ! tc qdisc del dev $REP ingress_block 1 ingress > /dev/null 2>&1
    ! tc qdisc del dev $REP2 ingress_block 1 ingress > /dev/null 2>&1
}

echo "Generating batches"
tc_batch 0 "block 1" $total $rules_per_file

title "Test reoffload while overwriting rules"
par_test 0

title "Test reoffload while deleting rules"
par_test 1

test_done
