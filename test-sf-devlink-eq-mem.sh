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

LOWEST_VALUE=64
SF_NUM=10

function test_with_default_eq_values() {
    title "Case with default eq values"
    local free_mem_before_default_eq_sf=$(get_free_memory)

    create_sfs $SF_NUM

    local dev=`sf_get_netdev 1`
    default_io_eq_size=`devlink_dev_get_param $dev io_eq_size`
    default_event_eq_size=`devlink_dev_get_param $dev event_eq_size`

    local free_mem_after_default_eq_sf=$(get_free_memory)
    total_mem_consumed_default_eq_sf=$(($free_mem_before_default_eq_sf - $free_mem_after_default_eq_sf))

    title "FreeMem with default EQ values"
    echo "Before creating SFs: $free_mem_before_default_eq_sf"
    echo "After creating SFs: $free_mem_after_default_eq_sf"
    echo "Total memory consumed: $total_mem_consumed_default_eq_sf"

    remove_sfs
}

function test_with_lowest_eq_values() {
    title "Case with lowest eq values"
    local free_mem_before_eq_sf=$(get_free_memory)

    create_sfs $SF_NUM

    devlink_dev_set_eq $LOWEST_VALUE $LOWEST_VALUE `devlink_get_sfs`

    local free_mem_after_eq_sf=$(get_free_memory)
    total_mem_consumed_lowest_eq_sf=$(($free_mem_before_eq_sf - $free_mem_after_eq_sf))

    title "FreeMem with lowest EQ values"
    echo "Before creating SFs: $free_mem_before_eq_sf"
    echo "After creating SFs: $free_mem_after_eq_sf"
    echo "Total memory consumed: $total_mem_consumed_lowest_eq_sf"

    remove_sfs
}

function run_test() {
    config_sriov 0 $NIC
    enable_switchdev $NIC
    test_with_default_eq_values
    test_with_lowest_eq_values

    echo "Default EQ values: io_eq_size=$default_io_eq_size, event_eq_size=$default_event_eq_size"
    echo "Lowest EQ values: io_eq_size=$LOWEST_VALUE, event_eq_size=$LOWEST_VALUE"

    title "Check if memory consumed with lowest EQ values is less than default EQ values"
    if [[ $total_mem_consumed_lowest_eq_sf -gt $total_mem_consumed_default_eq_sf ]]; then
        fail "Total memory consumed default values EQ ($total_mem_consumed_default_eq_sf) should be higher ($total_mem_consumed_lowest_eq_sf)"
    fi

    success
}

run_test
trap - EXIT
cleanup
test_done
