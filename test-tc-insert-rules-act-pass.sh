#!/bin/bash
#
# Test rule with action pass on vf
#
# e1652e37318e net/mlx5e: Support accept action on nic table

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov
enable_switchdev
unbind_vfs
bind_vfs
require_interfaces VF

title "Test action pass rule on $VF"
reset_tc $VF
tc_filter add dev $VF protocol ip parent ffff: prio 1 handle 1 flower skip_sw dst_ip 1.1.1.1 action pass
reset_tc $VF

test_done
