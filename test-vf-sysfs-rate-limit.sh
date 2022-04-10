#!/bin/bash
#
# Test VFs rate limit feature configuration using sysfs.
# [MLNX OFED] Bug SW #3025984: [ARAVA][VDPA]: Can't add vfs to the vf-group
# [MLNX OFED] Bug SW #3036473: [ASAP, OFED 5.6] Setting same group many times over same vf cause driver hang

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function config() {
    title "Config"
    config_sriov 2
    enable_switchdev
}

function cleanup() {
    title "Clean up"
    reload_modules
    config_sriov 0
    config_sriov 2
    enable_switchdev
}
trap cleanup EXIT

function set_vfs_rate_config() {
    local config=$1
    local value=$2
    local vf
    for vf in `ls -d /sys/class/net/$NIC/device/sriov/[0-9]*/$config`; do
        echo $value > $vf || fail "Failed to set $config to $value"
    done
}

function set_vf_group() {
    local vf_num=$1
    local group_num=$2
    echo $group_num > /sys/class/net/$NIC/device/sriov/$vf_num/group || fail "Failed to set group $group_num for $vf_num"
}

function set_group_rate_config() {
    local config=$1
    local group_num=$2
    local value=$3
    echo $value > /sys/class/net/$NIC/device/sriov/groups/$group_num/$config || fail "Failed to set $config to $value for group $group_num"
}

function verify_group_is_deleted() {
    local group_num=$1
    if [ -d "/sys/class/net/$NIC/device/sriov/groups/$group_num" ]; then
        fail "Failed group $group_num is not deleted"
    else
        success
    fi
}

function run() {
    title "Test setting vfs max_tx_rate to 1000"
    set_vfs_rate_config max_tx_rate 1000
    title "Test setting vfs min_tx_rate to 500"
    set_vfs_rate_config min_tx_rate 500
    title "Test setting first vf group to 5"
    set_vf_group 0 5
    title "Test setting second vf group to 100"
    set_vf_group 1 100
    title "Test setting group 5 max_tx_rate 5000"
    set_group_rate_config max_tx_rate 5 5000
    title "Test setting group 5 min_tx_rate 500"
    set_group_rate_config min_tx_rate 5 500
    title "Test changing second vf group to 5"
    set_vf_group 1 5
    title "Verify group 100 is deleted"
    verify_group_is_deleted 100
    title "Verify setting same group over same vf many times"
    set_vf_group 1 5
    set_vf_group 1 5
    set_vf_group 1 5
    success
}

config
run
cleanup
trap - EXIT
test_done
