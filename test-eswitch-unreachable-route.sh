#!/bin/bash
#
# Test adding unreachable route in switchdev mode
#
# Bug SW #2639066: mlx5_core driver crashes when a VRF device with a route is added with mlx5 devices in switchdev mode

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function test_route() {
    config_sriov 2
    enable_switchdev

    ip route add unreachable 1.1.1.0/24 || err "Failed adding unreachable route"
    ip route del 1.1.1.0/24
}


test_route
test_done
