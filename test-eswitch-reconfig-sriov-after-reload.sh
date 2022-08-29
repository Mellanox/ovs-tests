#!/bin/bash
#
# Test reconfig sriov after reload failure
# - add tc rule
# - reload mlx5 - expect to fail in old kernels because of existing tc rule.
# - try to reconfig sriov.
# Bug SW #3191223: reconfiguring sriov after failure in module reload fails

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 1
enable_switchdev
require_interfaces REP
reset_tc $REP


function do_test() {
    title "test reconfig sriov after reload module failure"

    tc filter add dev $REP protocol ip parent ffff: prio 1 \
        flower skip_sw \
        src_mac e1:22:33:44:33:11 \
        dst_mac e2:22:33:44:33:22 \
        action drop

    title "reload module. expect to fail in old kernels because tc rule exists."
    reload_modules &
    reload_modules_pid=$!
    wait $reload_modules_pid
    reload_modules_result=$?

    [ -e /sys/class/net/$REP ] && reset_tc $REP

    if [ $reload_modules_result != 0 ]; then
        load_modules
    fi

    title "check reconfig sriov"
    config_sriov 2 &
    reload_pid=$!
    wait $reload_pid
    reload_result=$?

    if [ $reload_result != 0 ]; then
        err "reconfig sriov failed"
        reload_modules
    fi
}

do_test
test_done
