#!/bin/bash
#
# Test PCI reset while in switchdev mode and reset again
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


config_sriov
enable_switchdev
pci_reset
pci_reset
enable_switchdev
test_done
