#!/bin/bash
#
# Test PCI reset while in switchdev mode and reload modules
#
# Bug SW #2805586: [Upstream] null-ptr-deref in mlx5e_suspend+0x9c/0x130 while resetting PCI in switchdev mode

my_dir="$(dirname "$0")"
. $my_dir/common.sh

if is_upstream; then
    # Check comments in Bug SW #2805586: [Upstream] null-ptr-deref in mlx5e_suspend+0x9c/0x130 while resetting PCI in switchdev mode
    add_expected_error_msg ".*E-Switch: Getting vhca_id for vport failed \(vport=.*,err=-67\)"
    # This is after Bug SW #3888602: [Upstream] vport X error -67 reading stats
    add_expected_error_msg ".*failed reading stats on vport .*, error -67"
fi

config_sriov
enable_switchdev
pci_reset
reload_modules
config_sriov
test_done
