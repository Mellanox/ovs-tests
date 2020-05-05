#!/bin/bash
#
# Test set vf vlan 0 works on switchdev but no other vlan id
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev_if_no_rep $REP

title "Test set vf vlan id 200 on $NIC - expected to fail"
ip link set $NIC vf 1 vlan 200 2>/dev/null && err "Expected to fail"

title "Test set vf vlan id 0 on $NIC"
ip link set $NIC vf 1 vlan 0 || err "Failed to set vf vlan id 0"

test_done
