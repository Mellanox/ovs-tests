#!/bin/bash
#
# Test reload of mlx5 core module.
#
# A
#   1. set mode switchdev
#   2. reload mlx5
# B
#   1. set mode switchdev
#   2. add tc rule to rep
#   3. add tc rule to pf
#   4. reload mlx5
#   5. look for kasan errors
# C
#   1. set mode legacy
#   2. add tc rule to pf
#   3. reload mlx5
#   4. look for kasan errors
#
# Bug SW #865685: unloading mlx5_core when there are tc rules results in a crash
# Bug SW #1497154: FW errors and use-after-free KASAN error after unloading mlx5_core
#

NIC=${1:-ens5f0}
REP=${NIC}_0

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function add_tc_rule_to_rep() {
    title "add tc rule to rep $REP"
    reset_tc $REP
    tc_filter add dev $REP protocol ip parent ffff: prio 1 \
        flower skip_sw indev $REP \
        src_mac e1:22:33:44:00:00 \
        dst_mac e2:22:33:44:00:00 \
        action drop
}

function add_tc_rule_to_pf() {
    title "add tc rule to pf"
    reset_tc $NIC
    tc_filter add dev $NIC protocol ip parent ffff: prio 2 \
        flower skip_sw indev $NIC \
        src_mac e1:22:33:44:00:01 \
        dst_mac e2:22:33:44:00:01 \
        action drop
}

function testA() {
    title "TEST A - switchdev mode without tc rules"
    unbind_vfs
    switch_mode_switchdev
    title "test reload modules"
    reload_modules
}

function testB() {
    title "TEST B - switchdev mode with tc rules"

    if [ "$devlink_compat" = 1 ]; then
       # not relevant in backport as mlx5_core is dependent on cls_flower
       # and we cannot remove cls_flower when there are rules.
       echo "Test not relevant in backport"
       return
    fi

    unbind_vfs
    switch_mode_switchdev
    echo "look for $REP"
    sleep 0.5
    if [ ! -e /sys/class/net/$REP ]; then
        err "Missing rep $REP"
        return
    fi
    add_tc_rule_to_rep
    add_tc_rule_to_pf
    title "test reload modules"
    reload_modules
}

function testC() {
    title "TEST C - legacy mode with tc rules"

    if [ "$devlink_compat" = 1 ]; then
       # not relevant in backport as mlx5_core is dependent on cls_flower
       # and we cannot remove cls_flower when there are rules.
       echo "Test not relevant in backport"
       return
    fi

    unbind_vfs
    switch_mode_legacy
    add_tc_rule_to_pf
    title "test reload modules"
    reload_modules
}

testA
testB
testC

test_done
