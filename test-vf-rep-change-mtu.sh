#!/bin/bash
#
# Change REPs MTU when nic up and nic down.
# Bug SW #1415031: changing representor mtu can lead to crash
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev_if_no_rep $REP
require_interfaces REP REP2

function run() {
    local nic=$1
    for mtu in 1000 1600 1500 ; do
        echo "set to $mtu"
        ip link set $nic mtu $mtu || err "Fiailed to set mtu to $nic"
    done
}


for i in $REP  ; do
    title "Change $i mtu when nic is up"
    ifconfig $i 0 up
    run $i
    title "Change $i mtu when nic is down"
    ifconfig $i down
    run $i
done

test_done
