#!/bin/bash
#
# Change number of channels and do devlink reload.
# Expect not to crash.
#
# Bug SW #2241106: [ASAP, OFED 5.1, Korg 5.6] Call trace and kernel panic calling devlink reload

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2 $NIC
enable_switchdev

ch=$(ethtool -l $NIC | grep Combined | tail -1 | cut -f2-)
if [ "$ch" == 4 ]; then
    ch=1
else
    ch=4
fi

title "Change channels to $ch"
ethtool -L $NIC combined $ch || fail "Failed to change channels"

title "Reload pci $PCI"
devlink dev reload pci/$PCI || fail "Failed to reload pci device"

test_done
