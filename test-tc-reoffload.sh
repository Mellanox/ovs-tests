#!/bin/bash
#
# This test verifies re-offload functionality when block that already has
# offloaded rules is attached to another qdisc. Expected behavior is that all
# existing rules are re-offloaded to new device and any new rules are offloaded
# to both devices.
#


total=${1:-20000}
bind_times=${2:-3}
let rules_per_file=$total/10

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

function require_ingress_block_support() {
    local e
    tc qdisc del dev $NIC ingress &>/dev/null
    tc qdisc del dev $NIC ingress_block 1 ingress &>/dev/null
    tc qdisc add dev $NIC ingress_block 1 ingress &>/dev/null
    e=$?
    tc qdisc del dev $NIC ingress_block 1 ingress &>/dev/null
    [ $e -ne 0 ] && fail "ingress_block is not supported"
}

require_ingress_block_support

echo "setup"
config_sriov 2 $NIC
enable_switchdev_if_no_rep $REP
config_sriov 2 $NIC2
enable_switchdev_if_no_rep $REP2

require_interfaces NIC NIC2 REP REP2
reset_tc $NIC
reset_tc $NIC2
reset_tc $REP
reset_tc $REP2

function cleanup() {
    tc qdisc del dev $NIC ingress_block 1 ingress > /dev/null 2>&1
    tc qdisc del dev $NIC2 ingress_block 1 ingress> /dev/null 2>&1
}
trap cleanup EXIT
cleanup

echo "Clean tc rules"
tc qdisc del dev $NIC ingress > /dev/null 2>&1
tc qdisc del dev $NIC2 ingress > /dev/null 2>&1
tc qdisc add dev $NIC ingress_block 1 ingress
tc qdisc add dev $NIC2 ingress_block 1 ingress

function bind_unbind_block() {
    local dev=$1
    local block=$2

    for ((i = 0; i < $bind_times; i++)); do
        sleep 1
        echo "Unbind iteration $i"
        tc qdisc del dev $dev ingress_block $block ingress &>/dev/null
        echo "Bind iteration $i"
        tc qdisc add dev $dev ingress_block $block ingress &>/dev/null
    done
}

function par_test() {
    local del=$1
    local max_rules=$total

    bind_unbind_block $NIC2 1 &

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
}

function do_test() {
    echo "Generating batches $skip"
    tc_batch 0 "block 1" $total $rules_per_file

    title "Test reoffload while overwriting rules"
    par_test 0

    title "Test reoffload while deleting rules"
    par_test 1
}

for skip in "" skip_sw ; do
    do_test
done

test_done
