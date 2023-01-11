#!/bin/bash

function no_output() {
    local a=`$@ 2>&1`
    [ -n "$a" ] && err $a && return 1
    return 0
}

function create_bridge_with_interfaces() {
    local bridge_name=$1
    local i
    shift

    ip link del name $bridge_name type bridge 2>/dev/null
    ip link add name $bridge_name type bridge
    iptables -A FORWARD -i $bridge_name -j ACCEPT

    for i in $@; do
        no_output ip link set $i master $bridge_name
    done

    ip link set $bridge_name up
    ip link set name $bridge_name type bridge ageing_time 200
}

function flush_bridge() {
    local bridge_name=$1

    ip link set $bridge_name type bridge fdb_flush
}

function verify_ping_ns() {
    local ns=$1
    local from_dev=$2
    local dump_dev=$3
    local dst_ip=$4
    local t=$5
    local npackets=$6
    local filter=${7:-icmp}

    echo "sniff packets on $dump_dev"
    timeout $t tcpdump -qnnei $dump_dev -c $npackets ${filter} &
    local tpid=$!
    sleep 0.5

    echo "run ping for $t seconds"
    ip netns exec $ns ping -I $from_dev $dst_ip -c $t -w $t -q && success || err "Ping failed"
    verify_no_traffic $tpid
}
