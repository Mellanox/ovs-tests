#!/bin/bash
#
# Test SF EQ memory optimizations memory check
#
# required mlxconfig is PF_BAR2_SIZE=3 PF_BAR2_ENABLE=1
# [MKT. BlueField-SW] Feature Request #2482519: EQ memory optimizations - OFED first
# [MLNX OFED] Bug SW #2248656: [MLNX OFED SF] Creating SF is causing a kfree for unknown address

my_dir="$(dirname "$0")"
. $my_dir/common.sh

if ! is_ofed ; then
    fail "This feature is supported only over OFED"
fi

require_cmd uuidgen
verify_mlxconfig_for_sf
declare -a UUIDS

function remove_sf() {
    title "Delete SFs"
    for uuid in "${UUIDS[@]}"; do
        echo 1 > /sys/bus/mdev/devices/$uuid/remove
    done
    UUIDS=()
}

function create_sf_without_eq() {
    title "Create $1 SFs without EQ"
    for i in $(seq 1 $1); do
        uuid=$(uuidgen)
        UUIDS+=($uuid)
        echo $uuid > /sys/class/infiniband/mlx5_0/device/mdev_supported_types/mlx5_core-local/create
        echo $uuid > /sys/bus/mdev/drivers/vfio_mdev/unbind
        echo 1 > /sys/bus/mdev/devices/$uuid/devlink-compat-config/disable_en
        echo 1 > /sys/bus/mdev/devices/$uuid/devlink-compat-config/roce_disable
        echo $uuid > /sys/bus/mdev/drivers/mlx5_core/bind
    done
}

function create_sf_with_eq() {
    title "Create $1 SFs with EQ"
    for i in $(seq 1 $1); do
        uuid=$(uuidgen)
        UUIDS+=($uuid)
        echo $uuid > /sys/class/infiniband/mlx5_0/device/mdev_supported_types/mlx5_core-local/create
        echo $uuid > /sys/bus/mdev/drivers/vfio_mdev/unbind
        echo 1 > /sys/bus/mdev/devices/$uuid/devlink-compat-config/disable_en
        echo 1 > /sys/bus/mdev/devices/$uuid/devlink-compat-config/roce_disable
        echo 1 > /sys/bus/mdev/devices/$uuid/devlink-compat-config/max_cmpl_eq_count
        echo 64 > /sys/bus/mdev/devices/$uuid/devlink-compat-config/cmpl_eq_depth
        echo 64 > /sys/bus/mdev/devices/$uuid/devlink-compat-config/async_eq_depth
        echo $uuid > /sys/bus/mdev/drivers/mlx5_core/bind
    done
}

function test_without_eq(){
    free_mem_before_no_eq_sf=$(get_free_memory)
    create_sf_without_eq $max_sfs_allowed
    sleep 1
    free_mem_after_no_eq_sf=$(get_free_memory)
    total_mem_consumed_no_eq_sf=$(($free_mem_before_no_eq_sf - $free_mem_after_no_eq_sf))

    title "FreeMem without EQ"
    echo "Before creating SFs: $free_mem_before_no_eq_sf"
    echo "After creating SFs: $free_mem_after_no_eq_sf"
    echo "Total memory consumed: $total_mem_consumed_no_eq_sf"

    remove_sf
}

function test_with_eq(){
    free_mem_before_eq_sf=$(get_free_memory)
    create_sf_with_eq $max_sfs_allowed
    sleep 1
    free_mem_after_eq_sf=$(get_free_memory)
    total_mem_consumed_eq_sf=$(($free_mem_before_eq_sf - $free_mem_after_eq_sf))

    title "FreeMem with EQ"
    echo "Before creating SFs: $free_mem_before_eq_sf"
    echo "After creating SFs: $free_mem_after_eq_sf"
    echo "Total memory consumed: $total_mem_consumed_eq_sf"

    remove_sf
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

max_sfs_allowed=$(cat /sys/class/infiniband/mlx5_0/device/mdev_supported_types/mlx5_core-local/max_mdevs)
run_test
test_done
