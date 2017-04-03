#!/bin/bash
#
# Test add and del flows at the same time
# 2. start adding rules in bg
# 3. sleep
# 4. start deleting rules
#
# Expected result: not to crash
#

NIC=${1:-ens5f0}
COUNT=2500
ADD_DEL_SLEEP=10

my_dir="$(dirname "$0")"
. $my_dir/common.sh

rep=${NIC}_0
if [ ! -e /sys/class/net/$rep ]; then
    fail "Missing rep $rep"
    exit 1
fi
vf=virtfn0
vfpci=$(basename `readlink /sys/class/net/$NIC/device/$vf`)
if [ ! -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
    echo "bind vf $vfpci"
    echo $vfpci > /sys/bus/pci/drivers/mlx5_core/bind
fi
reset_tc_nic $NIC
reset_tc_nic $rep

set -e

function add_rules() {
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc filter add dev $rep protocol ip parent ffff: \
            flower skip_sw indev $rep \
            src_mac e1:22:33:44:${num1}:$num2 \
            dst_mac e2:22:33:44:${num1}:$num2 \
            action drop || fail "Failed to add rule"
    done
    echo "add rules done"
}

function del_rules() {
    local pref=49152
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc filter del dev $rep protocol ip parent ffff: prio $((pref--)) || fail "Failed to del rule"
    done
    echo "del rules done"
}


title "start adding rules"
add_rules &
sleep $ADD_DEL_SLEEP
title "start deleting rules"
del_rules
reset_tc_nic $rep
success "Test success"
echo "done"
