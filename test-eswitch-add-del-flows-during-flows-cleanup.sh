#!/bin/bash
#
# Test eswitch flows cleanup while adding/deleting tc flows from userspace
#
# Case add:
# 1. start adding many tc rules
# 2. switch mode to legacy (cause eswitch flows cleanup)
#
# Case del:
# 1. add many tc rules
# 2. start deleting tc rules from nic/rep
# 3. switch mode to legacy (cause eswitch flows cleanup)
#
# Expected result: not to crash
#
# Bug SW #1013092: Kernel trace between flower configure/delete and mlx5 eswitch
# disable sriov
#

NIC=${1:-ens5f0}
VF=${2:-ens5f2}
COUNT=500

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev
rep=`get_rep 0`
if [ -z "$rep" ]; then
    fail "Missing rep $rep"
    exit 1
fi

function add_rules() {
    local nic=$1
    title "add $COUNT rules to $nic"
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc filter add dev $nic protocol ip parent ffff: \
            flower skip_sw indev $nic \
            src_mac e1:22:33:44:${num1}:$num2 \
            dst_mac e2:22:33:44:${num1}:$num2 \
            action drop || return
    done
}

function del_rules() {
    local nic=$1
    local pref=49152
    local first=true
    title "del rules from $nic"
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc filter del dev $nic protocol ip parent ffff: prio $((pref--))
        if [ "$?" != 0 ]; then
            if [ $first = true ]; then
                fail "Failed to del first rule"
            fi
            break
        fi
        first=false
    done
}

function test_switch_mode_to() {
    title "switch mode to $1"
    eval switch_mode_$1
    echo "switch mode $1 done"
}

function test_case_del_in_switchdev() {
    local case=$1

    title "Test del flows case in switchdev $case"
    test -e /sys/class/net/$case || fail "Cannot find $case"
    reset_tc_nic $case
    add_rules $case
    del_rules $case &
    sleep .2
    test_switch_mode_to legacy &
    wait
    reset_tc_nic $case
    success
}

function test_case_del_in_legacy() {
    local case=$1

    title "Test del flows case in legacy $case"
    test -e /sys/class/net/$case || fail "Cannot find $case"
    reset_tc_nic $case
    switch_mode_legacy
    add_rules $case
    del_rules $case &
    sleep .2
    test_switch_mode_to switchdev &
    wait
    reset_tc_nic $case
    success
}
function test_case_add_in_switchdev() {
    local case=$1

    title "Test add flows case in switchdev $case"
    test -e /sys/class/net/$case || fail "Cannot find $case"
    reset_tc_nic $case
    add_rules $case &
    sleep .2
    test_switch_mode_to legacy &
    wait
    reset_tc_nic $case
    success
}

function test_case_add_in_legacy() {
    local case=$1

    title "Test add flows case in legacy $case"
    test -e /sys/class/net/$case || fail "Cannot find $case"
    switch_mode_legacy
    add_rules $case &
    sleep .2
    test_switch_mode_to switchdev &
    wait
    reset_tc_nic $case
    success
}

function test_case_add_and_disable_sriov() {
    local case=$1

    title "Test add and disabled sriov case $case"
    test -e /sys/class/net/$case || fail "Cannot find $case"
    num=`cat /sys/class/net/$case/device/sriov_numvfs`
    if [ "$num" == "0" ]; then
        echo 2 > /sys/class/net/$case/device/sriov_numvfs
    fi
    add_rules $case &
    sleep .2
    echo 0 > /sys/class/net/$case/device/sriov_numvfs
    wait
    reset_tc_nic $case
    if [ "$num" != "0" ]; then
        echo $num > /sys/class/net/$case/device/sriov_numvfs
        set_macs $num
    fi
    success
}


## cases

test_case_add_and_disable_sriov $NIC

enable_switchdev_if_no_rep $rep
test_case_add_in_switchdev $rep
enable_switchdev_if_no_rep $rep
test_case_del_in_switchdev $rep

test_case_add_in_switchdev $NIC
test_case_del_in_switchdev $NIC

test_case_add_in_legacy $NIC
test_case_del_in_legacy $NIC

bind_vfs
test_case_add_in_switchdev $VF
test_case_del_in_switchdev $VF
unbind_vfs

test_done
