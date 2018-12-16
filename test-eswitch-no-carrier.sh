#!/bin/bash
#
# Bug SW #1124753: VF is in no-carrier state in legacy mode after bringup of its
# representor in switchdev mode
#

NIC=${1:-ens1f0}
VF=${2:-ens1f2}
REP=${3:-ens1f0_0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


unbind_vfs
enable_switchdev_if_no_rep $REP
set_macs 2
bind_vfs
sleep 1

# bring up rep is what triggers the issue
require_interfaces REP
ip link set dev $REP up
switch_mode_legacy
sleep 1
require_interfaces NIC VF
ip link set dev $NIC up
ip link set dev $VF up
carrier=`cat /sys/class/net/$VF/carrier`

if [ "$carrier" == "0" ]; then
    ip link show dev $VF
    err "VF $VF has no carrier"
fi

test_done
