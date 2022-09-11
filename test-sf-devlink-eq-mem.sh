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

function get_used_mem() {
    vmstat -s | grep -i "used memory" | awk {'print $1'}
}

function test_with_default_eq_values() {
    title "Case with default EQ values"
    local used_mem_start=$(get_used_mem)

    create_sfs $SF_NUM

    local dev=`sf_get_netdev 1`
    default_io_eq_size=`devlink_dev_get_param $dev io_eq_size`
    default_event_eq_size=`devlink_dev_get_param $dev event_eq_size`

    local used_mem_end=$(get_used_mem)
    total_used_mem_default_eq=$(($used_mem_end - $used_mem_start))

    title "Used memory with default EQ values"
    echo "Before creating SFs: $used_mem_start"
    echo "After creating SFs: $used_mem_end"
    echo "Total memory used: $total_used_mem_default_eq"


    remove_sfs
}

function test_with_lowest_eq_values() {
    title "Case with lowest EQ values"
    local used_mem_start=$(get_used_mem)

    create_sfs $SF_NUM

    devlink_dev_set_eq $LOWEST_VALUE $LOWEST_VALUE `devlink_get_sfs`

    local used_mem_end=$(get_used_mem)
    total_used_mem_lowest_eq=$(($used_mem_end - $used_mem_start))

    title "Used memory with lowest EQ values"
    echo "Before creating SFs: $used_mem_start"
    echo "After creating SFs: $used_mem_end"
    echo "Total memory used: $total_used_mem_lowest_eq"

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
    if [[ $total_used_mem_lowest_eq -gt $total_used_mem_default_eq ]]; then
        fail "Total memory used with default EQ values ($total_used_mem_default_eq) should be higher lowest ($total_used_mem_lowest_eq)"
    fi

    success
}

run_test
trap - EXIT
cleanup
test_done
