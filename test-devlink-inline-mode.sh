#!/bin/bash
#
# Test setting inline-mode through devlink
# 1. while vfs are bound (expected to fail)
# 2. while vfs are unbound
#

NIC=${1:-ens5f0}
PCI=$(basename `readlink /sys/class/net/$NIC/device`)
echo "NIC PCI $PCI"

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function get_inline_mode() {
    output=`devlink dev eswitch show pci/$PCI`
    echo $output
    mode=`echo $output | grep -o "inline-mode \w*" | awk {'print $2'}`
}

unbind_vfs

reset_tc_nic $NIC
rep=${NIC}_0
if [ -e /sys/class/net/$rep ]; then
    reset_tc_nic $rep
fi

set -e

old=`date +"%s"`

for i in `ls -1d /sys/class/net/$NIC/device/virt*`; do
    vfpci=$(basename `readlink $i`)
    if [ -e /sys/bus/pci/drivers/mlx5_core/$vfpci ]; then
        echo "unbind $vfpci"
        echo $vfpci > /sys/bus/pci/drivers/mlx5_core/unbind
    fi
done

now=`date +"%s"`
sec=`echo $now - $old + 1 | bc`
a=`journalctl -n20 --since="$sec seconds ago" | grep -m1 syndrome || true`
if [ "$a" != "" ]; then
    echo $a
    fail "Detected syndrome error in journalctl"
fi

title "test show"
devlink dev eswitch set pci/$PCI inline-mode link || fail "Failed to set mode link"
get_inline_mode
test $mode = "link" || fail "Expected mode link"
success

title "test fail change mode when flows are configured"
tc filter add dev $NIC protocol ipv6 parent ffff: \
    flower skip_sw indev $NIC \
    src_mac e1:22:33:44:00:01 \
    dst_mac e2:22:33:44:00:01 \
    action drop || fail "Failed to add rule"
devlink dev eswitch set pci/$PCI inline-mode transport && fail "Expected to fail changing mode"
get_inline_mode
test $mode = "link" || fail "Expected mode link"
success

reset_tc_nic $NIC
title "test set inline-mode transport"
devlink dev eswitch set pci/$PCI inline-mode transport || fail "Failed to set mode transport"
get_inline_mode
test $mode = "transport" || fail "Expected mode transport"
success

if [ -e /sys/class/net/$rep ]; then
    title "test fail to add ipv4 rule to rep"
    tc filter add dev $rep protocol ip parent ffff: \
        flower skip_sw indev $rep \
        src_mac e1:22:33:44:00:00 \
        dst_mac e2:22:33:44:00:00 \
        src_ip 1.1.1.1 \
        dst_ip 2.2.2.2 \
        action drop || success "Failed to add rule as expected"

    title "test fail to add ipv6 rule to rep"
    tc filter add dev $rep protocol ipv6 parent ffff: \
        flower skip_sw indev $rep \
        src_mac e1:22:33:44:00:00 \
        dst_mac e2:22:33:44:00:00 \
        src_ip 2001:0db8:85a3::8a2e:0370:7334 \
        dst_ip 2001:0db8:85a3::8a2e:0370:7335 \
        action drop || success "Failed to add rule as expected"
else
    warn "skip rule ipv6 test - cannot find $rep"
fi

title "test add ipv6 rule to pf"
tc filter add dev $NIC protocol ipv6 parent ffff: \
    flower skip_sw indev $NIC \
    src_mac e1:22:33:44:00:01 \
    dst_mac e2:22:33:44:00:01 \
    src_ip 2001:0db8:85a3::8a2e:0370:7334 \
    dst_ip 2001:0db8:85a3::8a2e:0370:7335 \
    action drop || fail "Failed to add rule"
success

title "test revert on set failure"
echo "bind last vf $vfpci"
echo $vfpci > /sys/bus/pci/drivers/mlx5_core/bind
echo "try to change inline-mode"
devlink dev eswitch set pci/$PCI inline-mode network || success "Failed set inline-mode as expected"
get_inline_mode
test $mode = "transport" || fail "Expected mode transport"
success

if [ -e /sys/class/net/$rep ]; then
    title "test add ipv6 rule"
    tc filter add dev $rep protocol ipv6 parent ffff: \
        flower skip_sw indev $rep \
        src_mac e1:22:33:44:00:00 \
        dst_mac e2:22:33:44:00:00 \
        src_ip 2001:0db8:85a3::8a2e:0370:7334 \
        action drop || fail "Failed to add rule"
    success
else
    warn "skip rule ipv6 test - cannot find $rep"
fi

echo "* reset"
reset_tc_nic $NIC
reset_tc_nic $rep
echo $vfpci > /sys/bus/pci/drivers/mlx5_core/unbind
devlink dev eswitch set pci/$PCI inline-mode link
echo "done"
