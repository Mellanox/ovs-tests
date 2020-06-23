#!/bin/bash
#
# Test sriov disable while adding tc flows from userspace
#
# Case add:
# 1. start adding many tc rules
# 2. disable sriov
#
# Expected result: not to crash
# 
# Bug RN #1013092: Kernel trace between flower configure/delete and mlx5 eswitch disable sriov
# Bug SW #1293937: Kernel trace between flower configure/delete and mlx5 eswitch disable sriov

NIC=${1:-ens5f0}
VF=${2:-ens5f2}
COUNT=500

my_dir="$(dirname "$0")"
. $my_dir/common.sh

# expected to work on upstream from kernel 5 or with ofed 5.1.
if ! is_ofed; then
    require_min_kernel_5
fi

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
        tc filter add dev $nic protocol ip parent ffff: prio 1 handle $i \
            flower skip_sw \
            src_mac e1:22:33:44:${num1}:$num2 \
            dst_mac e2:22:33:44:${num1}:$num2 \
            action drop &>/dev/null
    done
}

function test_case_add_and_disable_sriov() {
    local case=$1

    title "Test add and disable sriov case $case"
    test -e /sys/class/net/$case || fail "Cannot find $case"
    num=`cat /sys/class/net/$case/device/sriov_numvfs`
    config_sriov 2 $case
    reset_tc $case
    add_rules $case &
    sleep .2
    config_sriov 0 $case
    wait
    reset_tc $case
    if [ "$num" != "0" ]; then
        config_sriov $num $case
        set_macs $num
    fi
    success
}


## cases

test_case_add_and_disable_sriov $NIC

test_done
