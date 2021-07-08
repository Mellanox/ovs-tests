#!/bin/bash
#
# Test SF EQ memory optimizations memory check
#
# required OFED is built using --with-sf-cfg-drv
# [MKT. BlueField-SW] Feature Request #2482519: EQ memory optimizations - OFED first
# [MLNX OFED] Bug SW #2248656: [MLNX OFED SF] Creating SF is causing a kfree for unknown address

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

if ! is_ofed ; then
    fail "This feature is supported only over OFED"
fi

sf_with_cfg=1
sf_disable_roce=1
sf_disable_netdev=1

function cleanup() {
    remove_sfs >/dev/null
}
trap cleanup EXIT

function test_without_eq() {
    title "Case without eq"
    free_mem_before_no_eq_sf=$(get_free_memory)

    create_sfs $max_sfs_allowed
    fail_if_err "Failed to create sfs"

    free_mem_after_no_eq_sf=$(get_free_memory)
    total_mem_consumed_no_eq_sf=$(($free_mem_before_no_eq_sf - $free_mem_after_no_eq_sf))

    title "FreeMem without EQ"
    echo "Before creating SFs: $free_mem_before_no_eq_sf"
    echo "After creating SFs: $free_mem_after_no_eq_sf"
    echo "Total memory consumed: $total_mem_consumed_no_eq_sf"

    remove_sfs
}

function test_with_eq() {
    title "Case with eq"
    free_mem_before_eq_sf=$(get_free_memory)

    create_sfs $max_sfs_allowed
    fail_if_err "Failed to create sfs"

    config_sfs_eq 1 64 64

    free_mem_after_eq_sf=$(get_free_memory)
    total_mem_consumed_eq_sf=$(($free_mem_before_eq_sf - $free_mem_after_eq_sf))

    title "FreeMem with EQ"
    echo "Before creating SFs: $free_mem_before_eq_sf"
    echo "After creating SFs: $free_mem_after_eq_sf"
    echo "Total memory consumed: $total_mem_consumed_eq_sf"

    remove_sfs
}

function run_test() {
    test_without_eq
    test_with_eq

    title "Check if memory consumed with EQ sf is less than without EQ"
    if [[ $total_mem_consumed_eq_sf -gt $total_mem_consumed_no_eq_sf ]]; then
        fail "Total memory consumed without EQ sf should be bigger"
        return
    fi

    success
}

max_sfs_allowed=$(fw_query_val PF_TOTAL_SF)

if [ "$max_sfs_allowed" == 0 ]; then
    fail "PF_TOTAL_SF is 0"
fi

run_test
test_done
