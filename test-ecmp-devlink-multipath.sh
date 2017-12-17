#!/bin/bash
#
#  desc: TODO
#
#  test: TODO
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

reset_tc_nic $NIC
rep=${NIC}_0
if [ -e /sys/class/net/$rep ]; then
    reset_tc_nic $rep
fi


function enable_disable_multipath() {
    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs

    title "- Enable multipath"
    disable_multipath
    enable_multipath || err "Failed to enable multipath"

    title "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 2 > /sys/class/net/$NIC2/device/sriov_numvfs

    title "- show devlink shows multipath enabled"
    mode=`get_multipath_mode`
    if [ -z "$mode" ]; then
        mode='X'
    fi
    test $mode = "enable" || err "Expected multipath mode enabled but got $mode"

    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs

    title "- Disable multipath"
    disable_multipath || err "Failed to disable multipath"
}


function fail_to_disable_in_sriov() {
    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs

    title "- Enable multipath"
    disable_multipath
    enable_multipath || err "Failed to enable multipath"

    title "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 2 > /sys/class/net/$NIC2/device/sriov_numvfs

    title "- Verify cannot disable multipath while in SRIOV"
    disable_multipath 2>/dev/null && err "Disabled multipath while in SRIOV" || true
}

function fail_to_enable_in_sriov() {
    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs

    title "- Disable multipath"
    disable_multipath

    title "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs

    title "- Verify cannot enable multipath while in SRIOV"
    enable_multipath 2>/dev/null && err "Enabled multipath while in SRIOV" || true
}

function change_pf0_to_switchdev_and_back_to_legacy_with_multipath() {
    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs

    title "- Enable multipath"
    disable_multipath
    enable_multipath || err "Failed to enable multipath"

    title "- Enable SRIOV and switchdev"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
    enable_switchdev

    title "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
}

function do_test() {
    title $1
    eval $1 && success
}


do_test enable_disable_multipath
do_test fail_to_disable_in_sriov
do_test fail_to_enable_in_sriov
do_test change_pf0_to_switchdev_and_back_to_legacy_with_multipath

test_done
