#!/bin/bash
#
# Test PCI reset while in nic mode and config sriov
# reload modules again, seems there was a bug unloading modules got stuck.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


config_sriov 0
enable_legacy
pci_reset
config_sriov
reload_modules
test_done
