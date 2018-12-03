#!/bin/bash
#
# Test toggle sriov on and bring up vfs
#
# Bug SW #1590053: [JD] Failing to bring up 100 VFs net devices
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function get_vfs() {
    local nic=${1:-$NIC}
    local a
    local o=""
    for i in `ls -1d /sys/class/net/$nic/device/virtfn*` ; do
        a=`ls $i/net`
        o="$o $a"
    done
    echo $o
}

function bring_vfs_up() {
    for i in `get_vfs`; do
        ip link set dev $i up
    done
}

function run() {
    title "Toggle sriov on $NIC"

    config_sriov 0 $nic
    for i in 10 20 30 100; do
        echo "config $i vfs"
        time config_sriov $i $nic
        echo "bring vfs up"
        time bring_vfs_up
        echo "clean"
        config_sriov 0 $nic
    done

    config_sriov 2 $NIC
}


run
test_done
