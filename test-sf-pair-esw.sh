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
    local i sfs
    ip netns ls | grep -q ns0 && sfs=`ip netns exec ns0 devlink dev | grep -w sf`
    for i in $sfs; do
        ip netns exec ns0 devlink dev reload $i netns 1
    done
    ip -all netns delete
    remove_sfs
}

trap cleanup EXIT

function set_sf_esw() {
    local count=$1
    local i ids a sf

    title "Set SF eswitch"

    # Failing to change fw with sf inactive but works with unbind.
    unbind_sfs
    for i in `seq 68 $((68-1+$count))`; do
        ~roid/SWS/gerrit2/iproute2/devlink/devlink port function set pci/0000:08:00.0/327$i eswitch enable || err "Failed to set SF eswitch"
        ~roid/SWS/gerrit2/iproute2/devlink/devlink port show pci/0000:08:00.0/327$i
    done
    bind_sfs

    fail_if_err

    for i in `seq $count`; do
        a="SF$i"
        sf=${!a}
        echo "SF $sf phys_switch_id `cat /sys/class/net/$sf/phys_switch_id`" || fail "Failed to get SF switch id"
    done
}

function set_sf_switchdev() {
    local count=$1
    local i

    title "Set SF switchdev"

    for i in `seq 2 $((1+$count))`; do
        ip netns exec ns0 devlink dev eswitch set auxiliary/mlx5_core.sf.$i mode switchdev || fail "Failed to config SF switchdev"
    done
}

function reload_sfs_into_ns() {
    local count=$1

    title "Reload SF into ns0"

    ip netns add ns0
    for i in `seq 2 $((1+$count))`; do
        devlink dev reload auxiliary/mlx5_core.sf.$i netns ns0 || fail "Failed to reload SF"
    done
}

function verify_single_ib_device() {
    local expected=$1

    title "Verify single IB device with multiple ports"

    rdma link show | grep -w mlx5_0
    local count=`rdma link show | grep -w mlx5_0 | wc -l`
    if [ "$count" -ne $expected ]; then
        err "Expected $expected ports"
    else
        success
    fi
}

function config() {
    local count=$1

    title "Config"
    create_sfs $count
    set_sf_esw $count
    reload_sfs_into_ns $count
    set_sf_switchdev $count
    verify_single_ib_device $((count*2))
}

function test_ping_single() {
    local id=$1
    local a sf sf_rep ip1 ip2

    sf="eth$((-1+$id))"
    a="SF_REP$id"
    sf_rep=${!a}

    ip1="$id.$id.$id.1"
    ip2="$id.$id.$id.2"

    title "Verify ping SF$id $sf<->$sf_rep"

    ip netns exec ns0 ifconfig $sf $ip1/24 up
    ifconfig $sf_rep $ip2/24 up
    ping -w 2 -c 1 $ip1 && success || err "Ping failed for SF$id $sf<->$sf_rep"
}

function test_ping() {
    local count=$1
    local i

    for i in `seq $count`; do
        test_ping_single $i
    done
}

enable_switchdev
test_count=3
config $test_count
test_ping $test_count
trap - EXIT
cleanup
test_done
