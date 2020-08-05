#!/bin/bash
#
# Test reload mlx5 modules multiple times
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function reload2() {
    __ignore_errors=1
    reload_modules
    __ignore_errors=0
    check_kasan
}

function do_test() {
    reload2
    set_macs 2
    enable_switchdev
}

enable_switchdev
for i in `seq 5`; do
    title "test iteration $i"
    do_test
    sleep 2
done

test_done
