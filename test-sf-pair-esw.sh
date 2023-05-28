#!/bin/bash
#
# Test traffic from SF to SF REP when SF in switchdev mode.


my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    log "cleanup"
    for i in 2 3 4; do
        ip netns ls | grep -q ns0 && ip netns exec ns0 devlink dev reload auxiliary/mlx5_core.sf.$i netns 1
    done
    ip -all netns delete
    remove_sfs
}

trap cleanup EXIT

function config() {
    title "Config"
    create_sfs 3
    ~roid/SWS/gerrit2/iproute2/devlink/devlink port show pci/0000:08:00.0/32768
    ~roid/SWS/gerrit2/iproute2/devlink/devlink port show pci/0000:08:00.0/32769

    title "Set SF eswitch"

    # Failing to change fw with sf inactive but works with unbind.
    unbind_sfs
    for i in 68 69 70; do
        ~roid/SWS/gerrit2/iproute2/devlink/devlink port function set pci/0000:08:00.0/327$i eswitch enable || err "Failed to set SF eswitch"
        ~roid/SWS/gerrit2/iproute2/devlink/devlink port show pci/0000:08:00.0/327$i
    done
    bind_sfs
    for i in $SF1 $SF2 $SF3; do
        echo "SF $i phys_switch_id `cat /sys/class/net/$i/phys_switch_id`" || err "Failed to get SF switch id"
    done
    fail_if_err

    title "Reload SF into ns0"
    ip netns add ns0
    for i in 2 3 4; do
        devlink dev reload auxiliary/mlx5_core.sf.$i netns ns0 || fail "Failed to reload SF"
    done

    title "Set SF switchdev"
    for i in 2 3 4; do
        ip netns exec ns0 devlink dev eswitch set auxiliary/mlx5_core.sf.$i mode switchdev || fail "Failed to config SF switchdev"
    done
}

enable_switchdev
config
trap - EXIT
cleanup
test_done
