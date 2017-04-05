#!/bin/bash
#
# Test reload of mlx5 core module while adding tc flows from userspace
# 2. start reload of mlx5 core module in the background
# 3. sleep 5 seconds and start adding tc rules
# 4. reset tc
#
# Expected result: not to crash
#

NIC=${1:-ens5f0}
COUNT=500

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

echo "********** TEST `basename $0` **************" > /dev/kmsg

function add_rules() {
    local first=1
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc filter add dev $rep protocol ip parent ffff: \
            flower skip_sw indev $rep \
            src_mac e1:22:33:44:${num1}:$num2 \
            dst_mac e2:22:33:44:${num1}:$num2 \
            action drop
        if [ "$?" != 0 ]; then
            if [ "$first" == 1 ]; then
                fail "Failed to add rule"
            fi
            break
        fi
        first=false
    done
}

function reload_modules() {
    modprobe -r mlx5_ib mlx5_core devlink || fail "Failed to unload modules"
    modprobe -a devlink mlx5_core mlx5_ib || fail "Failed to load modules"
    a=`journalctl -n200 | grep KASAN || true`
    if [ "$a" != "" ]; then
        fail "Detected KASAN in journalctl"
    fi
    echo "reload modules done"
}

title "test reload modules"
reload_modules &
sleep 5
title "add $COUNT rules"
add_rules
sleep 5
reset_tc_nic $rep

test_done
