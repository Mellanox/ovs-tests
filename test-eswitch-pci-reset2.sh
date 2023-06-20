#!/bin/bash
#
# Test PCI reset while in switchdev mode and move back to switchdev
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


if [[ `uname -r` == *"upstream"* ]] || [[ `uname -r` == *"linust"* ]]; then
    # Check comments in Bug SW #2805586: [Upstream] null-ptr-deref in mlx5e_suspend+0x9c/0x130 while resetting PCI in switchdev mode
    add_expected_error_msg ".*E-Switch: Getting vhca_id for vport failed \(vport=.*,err=-67\)"
fi

config_sriov
enable_switchdev
pci_reset
enable_switchdev
test_done
