#!/bin/bash
#
# Test PCI reset while in switchdev mode and move back to switchdev
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


config_sriov
enable_switchdev
pci_reset
enable_switchdev
test_done
