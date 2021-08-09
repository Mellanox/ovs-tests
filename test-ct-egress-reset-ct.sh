#!/bin/bash
#
# Test reset_ct() was done when redirecting to another port.
#
# [PATCH net] net: sched: act_mirred: Reset ct info when mirror/redirect skb
#
# Bug SW #2656813: ASAP CX6Dx - TC offload breaks traffic from internal port (no tunnel) in OVN - host pod to vf pod

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

function config_veth() {
    ip link add veth0 type veth peer name veth1

    ip addr add $IP1/24 dev veth0
    ip link set veth0 up

    ip addr add $IP2/24 dev veth1
    ip link set veth1 up

    mac=`cat /sys/class/net/veth1/address`
    ip n r $IP2 dev veth0 lladdr $mac
}

function config_tc() {
    tc qdisc add dev veth0 clsact
    # The same with "action mirred egress mirror dev veth1" or "action mirred ingress redirect dev veth1"
    tc filter add dev veth0 egress chain 1 protocol ip flower ct_state +trk action mirred ingress mirror dev veth1
    tc filter add dev veth0 egress chain 0 protocol ip flower ct_state -inv action ct commit action goto chain 1
    tc qdisc add dev veth1 clsact
    tc filter add dev veth1 ingress chain 0 protocol ip flower ct_state +trk action drop
}

function cleanup() {
    ip link del dev veth0
}

function get_bytes() {
    local dev=$1
    tc -j -s filter show dev $dev ingress | jq ".[1].options.actions[0].stats.bytes"
}

function run_test() {
    title "Test egress reset ct"

    config_veth
    config_tc
    ping -q -c 10 -i 0.1 -w 1 -I veth0 $IP2
    if [ "$?" != "0" ]; then
        tc -s filter show dev veth1 ingress
        local bytes=`get_bytes veth1`
        if [ "$bytes" != "0" ]; then
            err "Matched unexpected rule"
        fi
        # ping expected not to work (send replies) without namespace, depending on network configuration.
    fi
    cleanup
}

run_test
test_done
