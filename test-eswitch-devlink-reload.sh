#!/bin/bash
#
# Test devlink reload command.
# Expect not to crash.
#
# Bug SW #2241106: [ASAP, OFED 5.1, Korg 5.6] Call trace and kernel panic calling devlink reload

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2 $NIC
enable_switchdev

title "Reload pci $PCI"
devlink dev reload pci/$PCI 2>&1 | tee /tmp/log
# if blocked as reload not supported don't fail the test
grep -q "Operation not supported" /tmp/log || fail "Failed to reload pci device"

test_done
