#!/bin/bash
#
# Test setting inline-mode through devlink
# 1. while vfs are bound (expected to fail)
# 2. while vfs are unbound
#

NIC=${1:-ens5f0}
REP=${2:-ens5f0_0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx5

enable_switchdev
unbind_vfs
reset_tc_nic $NIC
reset_tc_nic $REP

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
set_eswitch_inline_mode link || fail "Failed to set mode link"
mode=`get_eswitch_inline_mode`
test $mode = "link" || fail "Expected mode link but got $mode"
success

title "test fail change mode when flows are configured"
tc filter add dev $NIC protocol ip parent ffff: \
    flower skip_sw indev $NIC \
    src_mac e4:22:33:44:00:01 \
    dst_mac e4:22:33:44:00:01 \
    action drop || fail "Failed to add rule"
set_eswitch_inline_mode transport && fail "Expected to fail changing mode"
mode=`get_eswitch_inline_mode`
test $mode = "link" || fail "Expected mode link but got $mode"
success

reset_tc_nic $NIC
title "test set inline-mode transport"
set_eswitch_inline_mode transport || fail "Failed to set mode transport"
mode=`get_eswitch_inline_mode`
test $mode = "transport" || fail "Expected mode transport but got $mode"
success

title "test fail to add ipv4 rule to rep"
tc filter add dev $REP protocol ip parent ffff: \
    flower skip_sw indev $REP \
    src_mac e1:22:33:44:00:00 \
    dst_mac e2:22:33:44:00:00 \
    src_ip 1.1.1.1 \
    dst_ip 2.2.2.2 \
    action drop || success "Failed to add rule as expected"

title "test fail to add ipv6 rule to rep"
tc filter add dev $REP protocol ipv6 parent ffff: \
    flower skip_sw indev $REP \
    src_mac e1:22:33:44:00:00 \
    dst_mac e2:22:33:44:00:00 \
    src_ip 2001:0db8:85a3::8a2e:0370:7334 \
    dst_ip 2001:0db8:85a3::8a2e:0370:7335 \
    action drop || success "Failed to add rule as expected"

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
set_eswitch_inline_mode network || success "Failed set inline-mode as expected"
mode=`get_eswitch_inline_mode`
test $mode = "transport" || fail "Expected mode transport but got $mode"
success

if [ -e /sys/class/net/$REP ]; then
    title "test add ipv6 rule"
    tc filter add dev $REP protocol ipv6 parent ffff: \
        flower skip_sw indev $REP \
        src_mac e1:22:33:44:00:00 \
        dst_mac e2:22:33:44:00:00 \
        src_ip 2001:0db8:85a3::8a2e:0370:7334 \
        action drop || fail "Failed to add rule"
    success
else
    warn "skip rule ipv6 test - cannot find $REP"
fi

echo "* reset"
reset_tc_nic $NIC
reset_tc_nic $REP
echo $vfpci > /sys/bus/pci/drivers/mlx5_core/unbind
set_eswitch_inline_mode link

test_done
