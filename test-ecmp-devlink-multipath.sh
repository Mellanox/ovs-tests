#!/bin/bash
#
# Bug SW #1242632: [ECMP] Null pointer dereference when in multipath mode changing pf0 to switchdev and back to legacy
# Bug SW #1242476: [ECMP] Null dereference when multipath is enabled and ports in sriov mode
# Bug SW #1243769: [ECMP] null dereference unsetting multipath ready flag on module cleanup
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
require_multipath_support
reset_tc_nic $NIC


function disable_sriov() {
    echo "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_sriov() {
    enable_sriov_port1
    enable_sriov_port2
}

function enable_sriov_port1() {
    echo "- Enable SRIOV port1"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
}

function enable_sriov_port2() {
    echo "- Enable SRIOV port2"
    echo 2 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function activate_multipath() {
    echo "- Enable multipath"
    disable_sriov
    enable_sriov
    unbind_vfs $NIC
    unbind_vfs $NIC2
    enable_multipath || err "Failed to enable multipath"
}

function test_1_enable_disable_multipath() {
    activate_multipath

    echo "- show devlink shows multipath enabled"
    mode=`get_multipath_mode`

    if [ "$devlink_compat" = 1 ]; then
        test "x$mode" = "xenabled" || err "Expected multipath mode enabled but got $mode"
    else
        test "x$mode" = "xenable" || err "Expected multipath mode enabled but got $mode"
    fi

    echo "- Disable multipath"
    disable_multipath || err "Failed to disable multipath"
    disable_sriov
}

function test_2_fail_to_enable_when_vfs_bound() {
    activate_multipath
    disable_multipath
    bind_vfs
    enable_multipath 2>/dev/null && err "Enabled multipath while VFs bound" || true
}

function test_3_change_both_ports_to_switchdev_and_back() {
    activate_multipath
    enable_switchdev $NIC
    enable_switchdev $NIC2
    enable_legacy $NIC
    enable_legacy $NIC2
    disable_multipath || err "Failed to disable multipath"
    disable_sriov

    # leave where NIC is in sriov
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
}

function test_4_change_both_ports_to_switchdev_and_disable_sriov() {
    activate_multipath
    enable_switchdev $NIC
    enable_switchdev $NIC2
    disable_multipath || err "Failed to disable multipath"
    disable_sriov

    # leave where NIC is in sriov
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
}

function test_5_multipath_ready_and_reload_mlx5_core() {
    activate_multipath
    enable_switchdev $NIC
    enable_switchdev $NIC2

    echo "- Reload mlx5_core"
    if [ "$devlink_compat" = 1 ]; then
        service openibd force-restart
    else
        modprobe -r mlx5_ib mlx5_core || err "Failed to unload modules"
        modprobe -a mlx5_core mlx5_ib || err "Failed to load modules"
    fi

    # leave where NIC is in sriov
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
}


# Execute all test_* functions
for i in `declare -F | awk {'print $3'} | grep ^test_ | grep -v test_done` ; do
    title $i
    eval $i && success
done

test_done
