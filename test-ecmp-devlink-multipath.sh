#!/bin/bash
#
# Bug SW #1242632: [ECMP] Null pointer dereference when in multipath mode changing pf0 to switchdev and back to legacy
# Bug SW #1242476: [ECMP] Null dereference when multipath is enabled and ports in sriov mode
# Bug SW #1243769: [ECMP] null dereference unsetting multipath ready flag on module cleanup
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

reset_tc_nic $NIC

function disable_sriov() {
    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_sriov() {
    title "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 2 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_disable_multipath() {
    disable_sriov

    title "- Enable multipath"
    disable_multipath
    enable_multipath || err "Failed to enable multipath"

    enable_sriov

    title "- show devlink shows multipath enabled"
    mode=`get_multipath_mode`
    if [ -z "$mode" ]; then
        mode='X'
    fi

    if [ "$devlink_compat" = 1 ]; then
        test $mode = "enabled" || err "Expected multipath mode enabled but got $mode"
    else
        test $mode = "enable" || err "Expected multipath mode enabled but got $mode"
    fi

    disable_sriov

    title "- Disable multipath"
    disable_multipath || err "Failed to disable multipath"
}


function fail_to_disable_in_sriov() {
    disable_sriov

    title "- Enable multipath"
    disable_multipath
    enable_multipath || err "Failed to enable multipath"

    enable_sriov

    title "- Verify cannot disable multipath while in SRIOV"
    disable_multipath 2>/dev/null && err "Disabled multipath while in SRIOV" || true
}

function fail_to_enable_in_sriov() {
    disable_sriov

    title "- Disable multipath"
    disable_multipath

    title "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs

    title "- Verify cannot enable multipath while in SRIOV"
    enable_multipath 2>/dev/null && err "Enabled multipath while in SRIOV" || true
}

function change_pf0_to_switchdev_and_back_to_legacy_with_multipath() {
    disable_sriov

    title "- Enable multipath"
    disable_multipath
    enable_multipath || err "Failed to enable multipath"

    title "- Enable SRIOV and switchdev"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
    enable_switchdev

    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs

    title "- Disable multipath"
    disable_multipath || err "Failed to disable multipath"
}

function change_both_ports_to_switchdev_and_back_to_legacy_with_multipath() {
    disable_sriov

    title "- Enable multipath"
    disable_multipath
    enable_multipath || err "Failed to enable multipath"

    title "- Enable SRIOV and switchdev"
    enable_sriov
    enable_switchdev $NIC
    enable_switchdev $NIC2

    disable_sriov

    title "- Disable multipath"
    disable_multipath || err "Failed to disable multipath"

    # leave where NIC is in sriov
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
}

function multipath_ready_and_change_pf0_switchdev_legacy() {
    disable_sriov

    title "- Enable multipath"
    disable_multipath
    enable_multipath || err "Failed to enable multipath"

    title "- Enable SRIOV and switchdev"
    enable_sriov
    enable_switchdev $NIC
    enable_switchdev $NIC2

    disable_sriov

    title "- Enable SRIOV and switchdev"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
    enable_switchdev

    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs

    title "- Disable multipath"
    disable_multipath || err "Failed to disable multipath"

    # leave where NIC is in sriov
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
}

function multipath_ready_and_reload_mlx5_core() {
    disable_sriov

    title "- Enable multipath"
    disable_multipath
    enable_multipath || err "Failed to enable multipath"

    title "- Enable SRIOV and switchdev"
    enable_sriov
    enable_switchdev $NIC
    enable_switchdev $NIC2

    title "- Reload mlx5_core"
    if [ "$devlink_compat" = 1 ]; then
        service openibd force-restart
    else
        modprobe -r mlx5_ib mlx5_core || err "Failed to unload modules"
        modprobe -a mlx5_core mlx5_ib || err "Failed to load modules"
    fi

    # leave where NIC is in sriov
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
}

function do_test() {
    title $1
    eval $1 && success
}


do_test enable_disable_multipath
do_test fail_to_disable_in_sriov
do_test fail_to_enable_in_sriov
do_test change_pf0_to_switchdev_and_back_to_legacy_with_multipath
do_test change_both_ports_to_switchdev_and_back_to_legacy_with_multipath
do_test multipath_ready_and_change_pf0_switchdev_legacy
do_test multipath_ready_and_reload_mlx5_core

test_done
