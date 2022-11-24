#!/bin/bash
#
# Test reload mlx5 during mode change to legacy modules multiple times
#
# Unload modules can race with any other action like
# - set mode legacy
# - set mode switchdev
# - create VFs
# - etc
#
# Bug SW #2673893: Call Trace with kernel panic when changing switchdev mod and unloading the module

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function reload2() {
    local s=".$RANDOM"
    echo "sleep $s"
    sleep $s
    __ignore_errors=1
    reload_modules
    __ignore_errors=0
    config_sriov 2
    check_kasan
}

function do_test() {
    enable_legacy &
    reload2
    wait
    set_macs 2
    enable_switchdev
}

config_sriov 2
enable_switchdev
for i in `seq 5`; do
    title "test iteration $i"
    do_test
    sleep 2
done

test_done
