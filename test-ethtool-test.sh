#!/bin/bash
#
# Verify ethtool --test
# we dont support loopback test in switchdev mode but dont fail for that the entire ethtool test.
#
# Bug SW #2479091: [ASAP] ethtool test failed over uplink representor

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2 $NIC
enable_switchdev
ip link set dev $NIC up
ethtool --test $NIC || err "ethtool test failed"
test_done
