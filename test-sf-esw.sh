#!/bin/bash
#
# Test traffic from SF to SF REP when SF in switchdev mode.


my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    ip netns ls | grep -q ns0 && ip netns exec ns0 devlink dev reload auxiliary/mlx5_core.sf.2 netns 1
    ip -all netns delete
    remove_sfs
}

trap cleanup EXIT

function config() {
    title "Config"
    create_sfs 1

    title "Set SF esw enable"

    # Failing to change fw with sf inactive but works with unbind.
#    sf_inactivate pci/0000:08:00.0/32768
    unbind_sfs

    ~roid/SWS/gerrit2/iproute2/devlink/devlink port function set pci/0000:08:00.0/32768 esw_enable enable || err "Failed to set sf esw_enable"
    ~roid/SWS/gerrit2/iproute2/devlink/devlink port show pci/0000:08:00.0/32768

#    sf_activate pci/0000:08:00.0/32768
    bind_sfs
    fail_if_err

    title "Reload SF into ns0"
    ip netns add ns0
    devlink dev reload auxiliary/mlx5_core.sf.2 netns ns0 || fail "Failed to reload sf"
    SF1="eth0"

    title "Set SF switchdev"
    ip netns exec ns0 devlink dev eswitch set auxiliary/mlx5_core.sf.2 mode switchdev || fail "Failed to config sf switchdev"

    ip netns exec ns0 ifconfig $SF1 $IP1/24 up
    ifconfig $SF_REP1 $IP2 up
}

function run_traffic() {
    t=5

    title "Ping SF $SF1 -> SF_REP $SF_REP1, sniff $SF_REP1"
    timeout $t tcpdump -qnnei $SF_REP1 -c 5 "icmp or arp" &
    pid1=$!
    sleep 0.1
    ip netns exec ns0 timeout $((t+1)) ping -c 10 -i 0.1 $IP2
    verify_have_traffic $pid1

    title "Ping SF_REP $SF_REP1 -> SF $SF1, sniff $SF1"
    ip netns exec ns0 timeout $t tcpdump -qnnei $SF1 -c 5 "icmp or arp" &
    pid1=$!
    sleep 0.1
    timeout $((t+1)) ping -c 10 -i 0.1 $IP1
    verify_have_traffic $pid1
}

enable_switchdev
config
run_traffic
trap - EXIT
cleanup
test_done
