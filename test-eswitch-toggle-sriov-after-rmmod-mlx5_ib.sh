#!/bin/bash
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module mlx5_ib
require_cmd ibdev2netdev

config_sriov 2
enable_switchdev

function start1() {
    local want=6 # 2 vfs, 2 uplink reps and 2 vf reps

    title "Test rmmod mlx5_ib"
    rmmod mlx5_ib

    title "Reconfig sriov"
    config_sriov 0
    config_sriov 2

    count=`ibdev2netdev | wc -l`
    if [ $count != $want ]; then
        err "Found $count ib interfaces but expected $want"
    else
        success "Found $count ib interfaces"
    fi
}

function cleanup() {
    enable_legacy
    config_sriov 0
}

trap cleanup EXIT

start1

cleanup
trap - EXIT
test_done
