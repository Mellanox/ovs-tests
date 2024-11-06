#!/bin/bash
#
# Test OVS-DPDK hot-upgrade process.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

OVS_HOTUPGRADE='/usr/share/openvswitch/scripts/ovs-hotupgrade'
OVS_RUNDIR='/var/run/openvswitch'
PIDFILE="$OVS_RUNDIR/ovs-vswitchd.pid"
PIDFILE_UPGRADING="$OVS_RUNDIR/ovs-vswitchd.upgrading.pid"

function check_supported() {
    if [ ! -f $OVS_HOTUPGRADE ]; then
        warn "Cannot find $OVS_HOTUPGRADE. consider as not supported."
        return 1
    fi

    if [ ! -f $PIDFILE ]; then
        err "Cannot find $PIDFILE"
        return 1
    fi

    return 0
}

function case_without_bridge() {
    title "Case without a bridge."
    run
    check_log
    # No cleanup to test next case without restarting ovs normally.
}

function case_with_bridge() {
    title "Case with a bridge."
    config_simple_bridge_with_rep 1
    run
    check_bridge
    check_log
    cleanup_test
}

function run() {
    title "Execute $OVS_HOTUPGRADE"

    local pid1=`cat $PIDFILE`
    log "Current pid: $pid1"

    $OVS_HOTUPGRADE || err "ovs-hotupgrade script failed."
    sleep 2

    title "Wait for the upgrading pid file to be removed."
    # wait for the upgrade file.
    for i in `seq 5`; do
        sleep 1
        [ -e $PIDFILE_UPGRADING ] && break
    done
    # wait for the pid file.
    for i in `seq 5`; do
        sleep 1
        [ -e $PIDFILE ] && [ ! -e $PIDFILE_UPGRADING ] && break
    done

    local pid2=`cat $PIDFILE`
    log "pid after ovs-hotupgrade: $pid2"
    if [ -z "$pid2" ] || [ "$pid1" == "$pid2" ]; then
        err "Expected a new pid. skip rest of the checks."
        return
    fi

    title "Sleep a bit and check ovs pidfile and socket files."
    # Need to sleep a bit before next steps.
    sleep 5
    [ -f $PIDFILE ] || err "Missing pidfile $PIDFILE."

    title "Check ovs ctl files."
    local ctl1="$OVS_RUNDIR/ovs-vswitchd.$pid1.ctl"
    local ctl2="$OVS_RUNDIR/ovs-vswitchd.$pid2.ctl"
    [ -e $ctl1 ] && err "Expected $ctl1 to be removed."
    [ -e $ctl2 ] || err "Expected $ctl2 to exists."

    title "Check ndu-sock files."
    local ndu1="$OVS_RUNDIR/ndu-sock.$pid1"
    local ndu2="$OVS_RUNDIR/ndu-sock.$pid2"
    [ -e $ndu1 ] && err "Expected $ndu1 to be removed."
    [ -e $ndu2 ] || err "Expected $ndu2 to exists."
}

function check_bridge() {
    title "Check the bridge."
    local br="br-phy"
    ovs-vsctl show
    ovs-ofctl dump-flows $br || err "Cannot find bridge $br"
}

function check_log() {
    title "Check for errors from ovs daemon."
    journalctl_for_test | grep -i "vswitchd.*|ERR|"
    if [ $? -eq 0 ]; then
        err "openvswitch errors."
    fi
}

check_supported || test_done

trap cleanup_test EXIT
case_without_bridge
case_with_bridge
trap - EXIT
test_done
