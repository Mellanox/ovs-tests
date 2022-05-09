#!/bin/bash
#
# Test configurable VF/REP queue amount and depth
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

#Test configurable VF/REP queue amount and depth
vf_channels_path=/sys/module/mlx5_core/parameters/pre_probe_vf_num_of_channels
vf_rq_size_path=/sys/module/mlx5_core/parameters/pre_probe_vf_rq_size
vf_sq_size_path=/sys/module/mlx5_core/parameters/pre_probe_vf_sq_size

rep_channels_path=/sys/class/net/$NIC/pre_init_rep_num_of_channels
rep_rq_size_path=/sys/class/net/$NIC/pre_init_rep_rq_size
rep_sq_size_path=/sys/class/net/$NIC/pre_init_rep_sq_size

if [ ! -f "$vf_channels_path" ] || [ ! -f "$vf_rq_size_path" ] || \
     [ ! -f "$vf_sq_size_path" ] || [ ! -f "$rep_channels_path" ] || \
     [ ! -f "$rep_rq_size_path" ] || [ ! -f "$rep_sq_size_path" ]; then
     fail "can not access VF/REP queue config"
fi

function set_queue_amount_depth() {
    echo "$1" > $vf_channels_path
    echo "$2" > $vf_rq_size_path
    echo "$3" > $vf_sq_size_path
    echo "$4" > $rep_channels_path
    echo "$5" > $rep_rq_size_path
    echo "$6" > $rep_sq_size_path
}

function reset_queue_defaults() {
    title "Resetting queue config to defaults"
    set_queue_amount_depth 0 0 0 0 0 0
}

function get_channel_number() {
    local ifname=$1
    ethtool -l $ifname | grep "Combined:" | grep -o "[0-9]*" | tail -1
}

function get_sq_size() {
    local ifname=$1
    ethtool -g $ifname | grep "TX:" | grep -o "[0-9]*" | tail -1
}

function get_rq_size() {
    local ifname=$1
    ethtool -g $ifname | grep "RX:" | grep -o "[0-9]*" | tail -1
}

function create_vfs() {
    config_sriov 2 $NIC
    enable_switchdev $NIC
    bind_vfs $NIC
}

function destroy_vfs() {
    config_sriov 0 $NIC
}

create_vfs
require_interfaces NIC VF REP

def_vf_channels=`get_channel_number $VF`
def_vf_rq_size=`get_rq_size $VF`
def_vf_sq_size=`get_sq_size $VF`

def_rep_channels=`get_channel_number $REP`
def_rep_rq_size=`get_rq_size $REP`
def_rep_sq_size=`get_sq_size $REP`

function verify_vf_rep_queue_amount_depth() {
    title "Verify vf rep queue amount depth"
    local expect_vf_channels=$1
    local expect_vf_rq_size=$2
    local expect_vf_sq_size=$3

    local expect_rep_channels=$4
    local expect_rep_rq_size=$5
    local expect_rep_sq_size=$6

    local actual_vf_channels=`get_channel_number $VF`
    local actual_vf_rq_size=`get_rq_size $VF`
    local actual_vf_sq_size=`get_sq_size $VF`

    local actual_rep_channels=`get_channel_number $REP`
    local actual_rep_rq_size=`get_rq_size $REP`
    local actual_rep_sq_size=`get_sq_size $REP`

    if [ ! "$actual_vf_channels" -eq "$expect_vf_channels" ] || [ ! "$actual_vf_rq_size" -eq "$expect_vf_rq_size" ] || \
        [ ! "$actual_vf_sq_size" -eq "$expect_vf_sq_size" ] || [ ! "$actual_rep_channels" -eq "$expect_rep_channels" ] || \
        [ ! "$actual_rep_rq_size" -eq "$expect_rep_rq_size" ] || [ ! "$actual_rep_sq_size" -eq "$expect_rep_sq_size" ]; then
        fail "Expected: $expect_vf_channels $expect_vf_rq_size $expect_vf_sq_size $expect_rep_channels $expect_rep_rq_size $expect_rep_sq_size, actual: $actual_vf_channels $actual_vf_rq_size $actual_vf_sq_size $actual_rep_channels $actual_rep_rq_size $actual_rep_sq_size "
    fi
}

function test_vf_queue_config_validation() {
    title "Verify vf queue config on invalid numbers"

    title "Case #1: Verify vfs params will fallback to defaults if the requested values exceed the maximum supported values"
    echo 100000000 > $vf_channels_path
    echo 100000000 > $vf_rq_size_path
    echo 100000000 > $vf_sq_size_path
    create_vfs
    verify_vf_rep_queue_amount_depth $def_vf_channels $def_vf_rq_size $def_vf_sq_size $def_rep_channels $def_rep_rq_size $def_rep_sq_size
    destroy_vfs

    title "Case #2: Verify vfs params will fallback to defaults if the requested values are below the minimum supported values"
    echo 1 > $vf_rq_size_path
    echo 1 > $vf_sq_size_path
    create_vfs
    verify_vf_rep_queue_amount_depth $def_vf_channels $def_vf_rq_size $def_vf_sq_size $def_rep_channels $def_rep_rq_size $def_rep_sq_size
    destroy_vfs
}

function test_rep_queue_config() {
    local param_path=$1
    local value=$2
    local expect_val=$3
    local error_msg=$4
    echo $value > $param_path
    local actual_val=`cat $param_path`
    if [ ! $actual_val -eq $expect_val ]; then
        fail $error_msg
    fi
}

function test_rep_queue_config_fail() {
    local param_path=$1
    local value=$2
    local expect_val=0
    local err_msg="$param_path should be 0 but atually is $actual_value"
    test_rep_queue_config $param_path $value $expect_val $err_msg
}

function test_rep_queue_config_roundup() {
    local param_path=$1
    local value=$2
    local expect_val=$3
    local err_msg="Failed to roundup to $value to $expect_val for $param_path"
    test_rep_queue_config $param_path $value $expect_val $err_msg
}

function test_rep_queue_config_validation() {
    title "Verify rep queue config fails on invalid numbers"

    title "Case #1: Invalid number that exceeds maximum of supported channels(10)"
    test_rep_queue_config_fail $rep_channels_path 100000000

    title "Case #2: Invalid number that is below minimal of supported rq size(64)"
    test_rep_queue_config_fail $rep_rq_size_path 100000000

    title "Case #3: Invalid number that is below minimal of supported rq size(64)"
    test_rep_queue_config_fail $rep_rq_size_path 1

    title "Case #4: Invalid number that exceeds maximum of supported sq size(8196)"
    test_rep_queue_config_fail $rep_sq_size_path 100000000

    title "Case #5: Invalid number that is below minimal of supported sq size(64)"
    test_rep_queue_config_fail $rep_sq_size_path 1

    title "Case #6: Roundup numbers to the nearest upper one if it is not power of 2(rq)"
    test_rep_queue_config_roundup $rep_rq_size_path 513 1024

    title "Case #7: Roundup numbers to the nearest upper one if it is not power of 2(sq)"
    test_rep_queue_config_roundup $rep_sq_size_path 65 128
}

function verify_default_queue_config() {
    title "Verify defaults"
    local vf_channels=`cat $vf_channels_path`
    local vf_rq_size=`cat $vf_rq_size_path`
    local vf_sq_size=`cat $vf_sq_size_path`

    local rep_channels=`cat $rep_channels_path`
    local rep_rq_size=`cat $rep_rq_size_path`
    local rep_sq_size=`cat $rep_sq_size_path`

    if [ ! "$vf_channels" -eq 0 ] || [ ! "$vf_rq_size" -eq 0 ] || \
        [ ! "$vf_sq_size" -eq 0 ] || [ ! "$rep_channels" -eq 0 ] || \
        [ ! "$rep_rq_size" -eq 0 ] || [ ! "$rep_sq_size" -eq 0 ]; then
       fail "Wrong default values"
    fi
}

function test_vf_rep_queue_default_after_reload_validation() {
    title "Verify vf rep queue config is set to defaults after reloading kernel modules"
    stop_openvswitch
    reload_modules
    verify_default_queue_config
}

function test_vf_rep_queue_amount_depth() {
    declare -A queue_config=(
        ['vf_channels']=1
        ['vf_rq_size']=512
        ['vf_sq_size']=2048
        ['rep_channels']=10
        ['rep_rq_size']=2048
        ['rep_sq_size']=512
    )
    verify_default_queue_config
    title "Verify vf rep queue amount depth"

    title "Case #1: Verify vf rep queue amount depth under default config"
    create_vfs
    verify_vf_rep_queue_amount_depth $def_vf_channels $def_vf_rq_size $def_vf_sq_size $def_rep_channels $def_rep_rq_size $def_rep_sq_size
    destroy_vfs

    title "Case #2: Verify vf rep queue amount depth after config was changed"
    set_queue_amount_depth ${queue_config['vf_channels']} ${queue_config['vf_rq_size']} ${queue_config['vf_sq_size']} ${queue_config['rep_channels']} ${queue_config['rep_rq_size']} ${queue_config['rep_sq_size']}
    create_vfs
    verify_vf_rep_queue_amount_depth ${queue_config['vf_channels']} ${queue_config['vf_rq_size']} ${queue_config['vf_sq_size']} ${queue_config['rep_channels']} ${queue_config['rep_rq_size']} ${queue_config['rep_sq_size']}
    destroy_vfs
}

function cleanup() {
    reset_queue_defaults
    sleep 0.5
}
trap cleanup EXIT

function run() {
    test_vf_rep_queue_amount_depth
    reset_queue_defaults
    test_vf_queue_config_validation
    test_rep_queue_config_validation
    test_vf_rep_queue_default_after_reload_validation
}

run
trap - EXIT
cleanup
test_done
