#!/bin/bash
#
# Verify ovs doesn't have stale ukeys.
#
# JIRA SDN-2329
# [OVS] Bug SW #3629309: OVS revalidator high CPU caused by large number of stale UKEYs
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"

function cleanup() {
    echo "cleanup"
    ovs_clear_bridges
    ip link del veth0 &>/dev/null
    ip link del veth2 &>/dev/null
    ip -all netns delete
}

trap cleanup EXIT

function config() {

    echo "setup veth and ns"
    ip link add veth0 type veth peer name veth1
    ip link add veth2 type veth peer name veth3

    ifconfig veth0 $VM1_IP/24 up
    ifconfig veth1 up

    ip netns add ns0
    ip link set veth2 netns ns0
    ip netns exec ns0 ifconfig veth2 $VM2_IP/24 up
    ifconfig veth3 up

    echo "setup ovs"
    ovs-vsctl add-br brv-1
    ovs-vsctl add-port brv-1 veth1
    ovs-vsctl add-port brv-1 veth3

    sleep 2
}

function verify() {
    ovs-appctl upcall/show

    # With tc, offloaded flows is taken from tc_to_ufid_node hmap which
    # doesn't have a garbage collector.
    # The ukeys gets cleaned for stale ukeys in revalidator_sweep__().

    if ovs-appctl upcall/show | grep '(keys' | awk '{print $3}' | grep -qv '0)' ; then
        err "Expected 0 ukeys"
        return
    fi

    success
}

function test_ping_ovs_flush() {
    title "Test ping + ovs flush"
    for i in `seq 2`; do
        ping -q -c 1 $VM2_IP || err "Ping failed"
        ovs_flush_rules
    done
}

function test_ping_tc_flush() {
    title "Test ping + tc flush"
    for i in `seq 2`; do
        ping -q -c 1 $VM2_IP || err "Ping failed"
        tc filter del dev veth1 ingress
        tc filter del dev veth3 ingress
    done

    ping -q -c 1 $VM2_IP || err "Ping failed"

    # Set low max-idle for longer time than ovs_flush_rules() for sweep.
    ovs_conf_set max-idle 1
    # Cause seq_mismatch a few times for the sweep to do someting.
    local rev=$(ovs-appctl coverage/read-counter rev_reconfigure)
    echo "rev_reconfigure $rev"
    for i in `seq 5`; do
        ovs-vsctl add-port brv-1 ovs-p2 -- set interface ovs-p2 type=internal
        ovs-vsctl del-port ovs-p2
        sleep 1
    done
    ovs-appctl revalidator/wait
    local rev=$(ovs-appctl coverage/read-counter rev_reconfigure)
    echo "rev_reconfigure $rev"
    ovs_conf_remove max-idle
    ovs_flush_rules
}

function run() {
    test_ping_ovs_flush
    verify

    test_ping_tc_flush
    verify
}

start_clean_openvswitch
cleanup
config
run
trap - EXIT
cleanup
test_done
