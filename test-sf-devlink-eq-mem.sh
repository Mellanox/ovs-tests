#!/bin/bash
#
# Test SF EQ memory optimizations memory check
#
# required minimum kernel 5.17
# Feature Request #2633766: BlueField Memory - ICM consumption per SF/VF improvement
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh
. $my_dir/common-devlink.sh

function cleanup() {
    remove_sfs
}
trap cleanup EXIT

SF_NUM=10

function test_without_eq() {
    title "Case without eq"
    local free_mem_before_no_eq_sf=$(get_free_memory)

    create_sfs $SF_NUM

    local free_mem_after_no_eq_sf=$(get_free_memory)
    TOTAL_MEM_CONSUMED_NO_EQ_SF=$(($free_mem_before_no_eq_sf - $free_mem_after_no_eq_sf))

    title "FreeMem without EQ"
    echo "Before creating SFs: $free_mem_before_no_eq_sf"
    echo "After creating SFs: $free_mem_after_no_eq_sf"
    echo "Total memory consumed: $TOTAL_MEM_CONSUMED_NO_EQ_SF"

    remove_sfs
}

function test_with_eq() {
    title "Case with eq"
    local free_mem_before_eq_sf=$(get_free_memory)

    create_sfs $SF_NUM

    devlink_dev_set_eq 64 64 `devlink_get_sfs`

    local free_mem_after_eq_sf=$(get_free_memory)
    TOTAL_MEM_CONSUMED_EQ_SF=$(($free_mem_before_eq_sf - $free_mem_after_eq_sf))

    title "FreeMem with EQ"
    echo "Before creating SFs: $free_mem_before_eq_sf"
    echo "After creating SFs: $free_mem_after_eq_sf"
    echo "Total memory consumed: $TOTAL_MEM_CONSUMED_EQ_SF"

    remove_sfs
}

function run_test() {
    config_sriov 0 $NIC
    enable_switchdev $NIC
    test_without_eq
    test_with_eq

    title "Check if memory consumed with EQ sf is less than without EQ"
    if [[ $TOTAL_MEM_CONSUMED_EQ_SF -gt $TOTAL_MEM_CONSUMED_NO_EQ_SF ]]; then
        fail "Total memory consumed without EQ sf should be bigger"
    fi

    success
}

run_test
trap - EXIT
cleanup
test_done
