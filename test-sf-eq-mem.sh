#!/bin/bash
#
# Test SF EQ memory optimizations memory check
#
# required mlxconfig is PF_BAR2_SIZE=3 PF_BAR2_ENABLE=1
# [MKT. BlueField-SW] Feature Request #2482519: EQ memory optimizations - OFED first
# [MLNX OFED] Bug SW #2248656: [MLNX OFED SF] Creating SF is causing a kfree for unknown address

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf-mlxdevm.sh

verify_mlxconfig_for_sf

if ! is_ofed ; then
    fail "This feature is supported only over OFED"
fi

declare -a SF_REPS
declare -a SF_RDMADEVS

function remove_sfs() {
    title "Delete SFs"
    # WA Deleting SFs while they are binded is extremly slow need to unbind first to make it faster
    local sf_rdmadev
    for sf_rdmadev in "${SF_RDMADEVS[@]}"; do
        sf_unbind $sf_rdmadev
    done

    local rep
    for rep in "${SF_REPS[@]}"; do
        sf_inactivate $rep
        delete_sf $rep
    done

    SF_REPS=()
    SF_RDMADEVS=()
}

function create_sfs_without_eq() {
    title "Create $1 SFs without EQ"
    local i
    for i in $(seq 1 $1); do
        create_sf 0 $i
        sleep 0.5

        local rep=$(get_sf_rep $i)
        sf_disable_roce $rep
        sf_activate $rep

        local sf_rdmadev=$(get_sf_rdmadev $i)
        sf_set_param $sf_rdmadev disable_netdev true
        sf_cfg_unbind $sf_rdmadev
        sf_bind $sf_rdmadev
        sleep 1

        SF_RDMADEVS+=($sf_rdmadev)
        SF_REPS+=($rep)
    done
}

function create_sfs_with_eq() {
    title "Create $1 SFs with EQ"
    local i
    for i in $(seq 1 $1); do
        create_sf 0 $i
        sleep 0.5

        local rep=$(get_sf_rep $i)
        sf_disable_roce $rep
        sf_activate $rep

        local sf_rdmadev=$(get_sf_rdmadev $i)
        sf_set_param $sf_rdmadev max_cmpl_eqs 1
        sf_set_param $sf_rdmadev cmpl_eq_depth 64
        sf_set_param $sf_rdmadev async_eq_depth 64
        sf_set_param $sf_rdmadev disable_netdev true
        sf_set_param $sf_rdmadev disable_fc true

        sf_cfg_unbind $sf_rdmadev
        sf_bind $sf_rdmadev
        sleep 1

        SF_RDMADEVS+=($sf_rdmadev)
        SF_REPS+=($rep)
    done
}

function test_without_eq(){
    free_mem_before_no_eq_sf=$(get_free_memory)
    create_sfs_without_eq $max_sfs_allowed
    sleep 1
    free_mem_after_no_eq_sf=$(get_free_memory)
    total_mem_consumed_no_eq_sf=$(($free_mem_before_no_eq_sf - $free_mem_after_no_eq_sf))

    title "FreeMem without EQ"
    echo "Before creating SFs: $free_mem_before_no_eq_sf"
    echo "After creating SFs: $free_mem_after_no_eq_sf"
    echo "Total memory consumed: $total_mem_consumed_no_eq_sf"

    remove_sfs
}

function test_with_eq(){
    free_mem_before_eq_sf=$(get_free_memory)
    create_sfs_with_eq $max_sfs_allowed
    sleep 1
    free_mem_after_eq_sf=$(get_free_memory)
    total_mem_consumed_eq_sf=$(($free_mem_before_eq_sf - $free_mem_after_eq_sf))

    title "FreeMem with EQ"
    echo "Before creating SFs: $free_mem_before_eq_sf"
    echo "After creating SFs: $free_mem_after_eq_sf"
    echo "Total memory consumed: $total_mem_consumed_eq_sf"

    remove_sfs
}

function run_test(){
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
run_test
test_done
