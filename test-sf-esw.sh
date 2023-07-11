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

function config() {
    title "Config"
    create_sfs 1

    set_sf_eswitch
    reload_sfs_into_ns
    set_sf_switchdev

    SF1="eth0"
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
