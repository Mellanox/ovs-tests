#!/bin/sh
#
# 1. set legacy mode
# 2. add tc rule
# 3. change mode to switchdev
# 4. del rules
#
# Expected result: not to crash
#
# Bug SW #935342: Adding rule in legacy mode and then deleting in switchdev mode
# results in null deref
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

vf=virtfn0
vfpci=$(basename `readlink /sys/class/net/$NIC/device/$vf`)
if [ ! -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
    echo "bind vf $vfpci"
    echo $vfpci > /sys/bus/pci/drivers/mlx5_core/bind
fi
reset_tc_nic $NIC

set -e
echo "********** TEST `basename $0` **************" > /dev/kmsg

COUNT=5
NIC1=$NIC

function add_rules() {
    echo "add rules"
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc filter add dev $NIC1 protocol ip parent ffff: \
            flower skip_sw indev $NIC1 \
            src_mac e1:22:33:44:${num1}:$num2 \
            dst_mac e2:22:33:44:${num1}:$num2 \
            action drop || fail "Failed to add rule"
    done
}

title "Add rule in legacy mode and reset in switchdev"
switch_mode_legacy
add_rules
unbind_vfs
switch_mode_switchdev
reset_tc_nic $NIC

success "Test success"
echo "done"
