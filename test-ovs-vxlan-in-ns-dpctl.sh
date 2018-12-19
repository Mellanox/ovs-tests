#!/bin/bash
#
# Test ovs with vxlan rules and dump flows with dpctl
#
# Bug SW #1465595: ovs-dpctl dump-flows command failed when using non default vxlan port

my_dir="$(dirname "$0")"

USE_DPCTL=1
VXLAN_PORT=4000
. $my_dir/test-ovs-vxlan-in-ns.sh
