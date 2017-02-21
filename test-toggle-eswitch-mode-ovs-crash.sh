#!/bin/sh
#
# Test toggle e-switch mode
# - Set mode switchdev
# - Config OVS bridge datapath_type=hw_netlink
# - Add ports
# - Set mode legacy
# - Check openvswitch didn't crash
#
# Bug SW #895956: Segmentation fault after changing e-switch mode from switchdev
#

NIC=${1:-ens5f0}
BRIDGE="ovs-vx"

my_dir="$(dirname "$0")"
. $my_dir/common.sh

bind_vfs
reset_tc_nic $NIC

set -e
title2

title "verify ovs is running"
service openvswitch restart
sleep 2
pidof ovs-vswitchd || fail "ovs-vswitchd not running"

title "set mode switchdev"
unbind_vfs
switch_mode_switchdev

title "add bridge"
ovs-vsctl del-br $BRIDGE || true
ovs-vsctl add-br $BRIDGE

title "add bridge ports"
ovs-vsctl -- add-port $BRIDGE ${NIC}_0
ovs-vsctl -- add-port $BRIDGE ${NIC}_1
ovs-vsctl -- add-port $BRIDGE $NIC
ovs-vsctl show

title "set mode legacy"
switch_mode_legacy

# ovs catch crashes and restart it self but it takes a second.
sleep 2

title "verify ovs is running and no crashes"
pidof ovs-vswitchd || fail "ovs-vswitchd not running"
# I dont see this anymore. belongs to v2.5 ?
# ps aux | grep ovs-vswitchd | grep healthy || fail "ovs-vswitchd is not healthy"

title "set mode switchdev"
unbind_vfs
switch_mode_switchdev
ovs-vsctl del-br $BRIDGE || true

success "Test success"
echo "done"
