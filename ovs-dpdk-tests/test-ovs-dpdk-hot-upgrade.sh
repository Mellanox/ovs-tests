#!/bin/bash
#
# Test OVS-DPDK hot-upgrade process.
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

OVS_RUNDIR='/var/run/openvswitch'
PIDFILE="$OVS_RUNDIR/ovs-vswitchd.pid"
PIDFILE_UPGRADING="$OVS_RUNDIR/ovs-vswitchd.upgrading.pid"

function config() {
    config_sriov 2
    enable_switchdev
    start_clean_openvswitch
}

function is_file_exists() {
    bf_wrap "test -e $1"
}

function cat_file() {
    bf_wrap "cat $1"
}

function ovs_vswitchd_pids() {
    bf_wrap "pidof ovs-vswitchd"
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
    title "Hotupgrade ovs-vswitchd"

    local pid1=`cat_file $PIDFILE`
    log "Current pid: $pid1"

    reload_ovs_vswitchd || err "ovs-vswitchd hotupgrade failed."
    sleep 2

    title "Wait for the upgrading pid file to be removed."
    # wait for the upgrade file.
    for i in `seq 10`; do
        sleep 1
        is_file_exists $PIDFILE_UPGRADING && break
    done
    # wait for the pid file.
    for i in `seq 10`; do
        sleep 1
        is_file_exists $PIDFILE && ! is_file_exists $PIDFILE_UPGRADING && break
    done

    local pid2=`cat_file $PIDFILE`
    log "pid after ovs-vswitchd reload: $pid2"
    if [ -z "$pid2" ] || [ "$pid1" == "$pid2" ]; then
        err "Expected a new pid. skip rest of the checks."
        return
    fi

    title "Wait for a single ovs-vswitchd process."
    echo "ovs-vswitchd pids: $(ovs_vswitchd_pids)"
    for i in `seq 30`; do
        sleep 1
        local count=$(ovs_vswitchd_pids | wc -w)
        [ $count -le 1 ] && break
    done
    [ $count -ne 1 ] && err "Expected a single ovs-vswitchd process."

    title "Check ovs pidfile."
    is_file_exists $PIDFILE || err "Missing pidfile $PIDFILE."

    title "Check ovs ctl files."
    local ctl1="$OVS_RUNDIR/ovs-vswitchd.$pid1.ctl"
    local ctl2="$OVS_RUNDIR/ovs-vswitchd.$pid2.ctl"
    is_file_exists $ctl1 && err "Expected $ctl1 to be removed."
    is_file_exists $ctl2 || err "Expected $ctl2 to exists."

    title "Check ndu-sock files."
    local ndu1="$OVS_RUNDIR/ndu-sock.$pid1"
    local ndu2="$OVS_RUNDIR/ndu-sock.$pid2"
    is_file_exists $ndu1 && err "Expected $ndu1 to be removed."
    is_file_exists $ndu2 || err "Expected $ndu2 to exists."
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

config
trap cleanup_test EXIT
case_without_bridge
case_with_bridge
trap - EXIT
test_done
