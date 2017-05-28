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
# Bug SW #1013092: Missing RTNL lock protection before calling tc delete flows
# cleanup function
#

NIC=${1:-ens5f0}
COUNT=500

my_dir="$(dirname "$0")"
. $my_dir/common.sh

rep=${NIC}_0
enable_switchdev_if_no_rep $rep
if [ ! -e /sys/class/net/$rep ]; then
    fail "Missing rep $rep"
    exit 1
fi
reset_tc_nic $NIC
reset_tc_nic $rep


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
                fail "Failed to del rule"
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
    enable_switchdev_if_no_rep $rep
    add_rules $case
    del_rules $case &
    sleep .2
    test_switch_mode_to legacy &
    sleep 5
    reset_tc_nic $NIC
    reset_tc_nic $rep
    wait
    success
}

function test_case_del_in_legacy() {
    local case=$1

    title "Test del flows case in legacy $case"
    switch_mode_legacy
    add_rules $case
    del_rules $case &
    sleep .2
    test_switch_mode_to switchdev &
    sleep 5
    reset_tc_nic $NIC
    reset_tc_nic $rep
    wait
    success
}
function test_case_add_in_switchdev() {
    local case=$1

    title "Test add flows case in switchdev $case"
    enable_switchdev_if_no_rep $rep
    add_rules $case &
    sleep .2
    test_switch_mode_to legacy &
    sleep 5
    reset_tc_nic $NIC
    reset_tc_nic $rep
    wait
    success
}

test_case_add_in_switchdev $rep
test_case_del_in_switchdev $rep

test_case_add_in_switchdev $NIC
test_case_del_in_switchdev $NIC


test_done
