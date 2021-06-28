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

if ! is_ofed ; then
    fail "This feature is supported only over OFED"
fi

function create_sfs_with_eq() {
    title "Create $1 SFs with EQ"
    local i
    for i in $(seq 1 $1); do
        create_sf 0 $i
        sleep 0.5

        local rep=$(get_sf_rep $i)
        sf_disable_roce $rep
        sf_activate $rep

        local sf_dev=$(sf_get_dev $i)
        sf_set_param $sf_dev max_cmpl_eqs 1
        sf_set_param $sf_dev cmpl_eq_depth 64
        sf_set_param $sf_dev async_eq_depth 64
        sf_set_param $sf_dev disable_netdev true
        sf_set_param $sf_dev disable_fc true

        sf_cfg_unbind $sf_dev
        sf_bind $sf_dev
        sleep 1

        SF_DEVS+=($sf_dev)
        SF_REPS+=($rep)
    done
}

function test_without_eq() {
    free_mem_before_no_eq_sf=$(get_free_memory)
    sf_disable_netdev=1
    create_sfs $max_sfs_allowed
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

if [ "$max_sfs_allowed" == 0 ]; then
    fail "PF_TOTAL_SF is 0"
fi

run_test
test_done
