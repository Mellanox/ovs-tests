#!/bin/bash
#
# Test reload mlx5 modules multiple times
# Expected machine not to freeze.
#
# RM# TODO
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

set -e

function reload_mlx5() {
    title "test reload modules"
    modprobe -r mlx5_ib mlx5_core devlink || fail "Failed to unload modules"
    modprobe -a devlink mlx5_core mlx5_ib || fail "Failed to load modules"
    check_kasan
}

function do_test() {
    reload_mlx5
    set_macs 2
    switch_mode_switchdev
}

for i in `seq 10`; do
    title "test iteration $i"
    do_test
    sleep 5
done

test_done
