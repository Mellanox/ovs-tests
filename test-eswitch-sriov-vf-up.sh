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
    local t1
    local t2
    local x=80

    title "Toggle sriov on $NIC"

    config_sriov 0 $nic
    for i in 10 20 100 112 114 ; do

        if [ $i -gt 100 ]; then
            x=180
        fi

        echo "config $i vfs"
        t1=`get_time`
        time config_sriov $i $nic
        t2=`get_time`
        let t1=t2-t1
        if [ $t1 -gt $x ]; then
            err "Expected config to take less than $x seconds"
        fi
        echo "bring vfs up"
        time bring_vfs_up
        echo "clean"
        config_sriov 0 $nic
    done

    config_sriov 2 $NIC
}


run
test_done
