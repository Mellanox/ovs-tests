#!/bin/bash
#
# Test accessing vf devlink compat directory attributes does not cause a call trace.
# Bug SW #2660247: [CMCC] CX6Dx HW vDPA forwarder gets kernel crash when calling "mlx5e_free_flow_meter" or "esw_compat_read"

my_dir="$(dirname "$0")"
. $my_dir/common.sh

if ! is_ofed ; then
    fail "This test is supported only over OFED"
fi

function config() {
    config_sriov 2
    enable_switchdev
    bind_vfs
    require_interfaces VF
}

function test_vf_devlink_compat() {
   title "Access all devlink compat attributes for $VF"
   for i in `ls -1 /sys/class/net/$VF/compat/devlink/*`; do
        echo "Attribute `basename $i`"
        cat $i &>/dev/null
   done
}

config
test_vf_devlink_compat
test_done