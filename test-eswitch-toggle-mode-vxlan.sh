#!/bin/bash
#
# Test setting legacy mode from switchdev mode while vxlan is configured
#
# Bug SW #2578228: syndrome (0x3ad80c) when restarting the driver after creating vxlan on switchdev
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov
enable_switchdev
ip link add vxlan4084 type vxlan id 4084 remote ::14:141:89:6 dev $NIC dstport 19501
ip link set dev vxlan4084 up
enable_legacy
enable_switchdev
ip link del vxlan4084
test_done
