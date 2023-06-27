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

function get_all_sf_pci() {
    devlink port show | grep sfnum | awk {'print $1'}
}

function set_sf_esw() {
    local count=$1
    local i ids a sf port

    title "Set SF eswitch"

    # Failing to change fw with sf inactive but works with unbind.
    unbind_sfs
    for port in `get_all_sf_pci`; do
        port=${port%:}
        devlink_port_eswitch_enable $port
        devlink_port_show $port
    done
    bind_sfs

    fail_if_err

    for sf_dev in `get_aux_sf_devices`; do
        sf=`basename $sf_dev/net/*`
        echo "SF $sf phys_switch_id `cat $sf_dev/net/*/phys_switch_id`" || fail "Failed to get SF switch id"
    done
}

function set_sf_switchdev() {
    title "Set SF switchdev"

    for sf_dev in `get_aux_sf_devices`; do
        local i=`basename $sf_dev`
        ip netns exec ns0 devlink dev eswitch set auxiliary/$i mode switchdev || fail "Failed to config SF switchdev"
    done
}

function reload_sfs_into_ns() {
    title "Reload SF into ns0"

    ip netns add ns0
    for sf_dev in `get_aux_sf_devices`; do
        local i=`basename $sf_dev`
        devlink dev reload auxiliary/$i netns ns0 || fail "Failed to reload SF"
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
    reload_sfs_into_ns
    set_sf_switchdev
    log "Wait for shared fdb wq"
    sleep 3
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
