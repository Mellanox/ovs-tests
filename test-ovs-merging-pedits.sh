#!/bin/bash
#
# Test OVS doesn't merge header rewrite actions and keeps ordering.
#
# Bug SW #2894058 tc filter output is missing DNAT action at ip+16

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev
require_interfaces REP NIC

dump_sleep=":"

function add_flow_dump_tc() {
    local flow=$1
    local actions=$2
    local dev=$3
    local cmd="ovs-appctl dpctl/add-flow \"$flow\" \"$actions\" ; $dump_sleep ; tc filter show dev $dev ingress"
    local m=`eval $cmd`

    [ -z "$m" ] && m=`eval $cmd`

    if [ -z "$m" ]; then
        err "Failed to add test flow: $flow"
        return 1
    fi

    output=$m
    return 0
}

function cleanup() {
    ovs_clear_bridges &>/dev/null
    reset_tc $NIC $REP
}
trap cleanup EXIT

function run() {
    cleanup

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $NIC
    ovs-vsctl add-port br-ovs $REP

    local filter="ufid:c5f9a0b1-3399-4436-b742-30825c64a1e5,recirc_id(0),in_port(2),eth_type(0x0800),eth(),ipv4(proto=6),tcp()"
    local actions="set(ipv4(ttl=3)),3,set(ipv4(ttl=4))"

    title "Add dpctl flow"
    add_flow_dump_tc $filter $actions $NIC
    local rc=$?

    if [ $rc -ne 0 ]; then
        return
    fi

    title "Verify TC rule"
    echo -e $output

    echo $output | grep -q "pedit .* mirred .* pedit"
    if [ $? -eq 0 ]; then
        success
    else
        err "expected actions pedit,mirred,pedit."
    fi

    # catch ovs parsing error
    local logfile="/var/log/openvswitch/ovs-vswitchd.log"
    if [ -f $logfile ]; then
        tail -n50 $logfile | grep "expected act csum with flags" && err "error in ovs logfile"
    fi
}

run
test_done
