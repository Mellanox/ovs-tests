#!/bin/bash

if ! hash iperf3 2>/dev/null
then
    fail "Iperf3 is not installed!"
fi

function setup_veth() {
    local veth1=$1
    local ip1=$2
    local veth2=$3
    local ip2=$4

    echo "setup veth and ns"
    ip link add $veth1 type veth peer name $veth2
    ip addr add $ip1/24 dev $veth1
    ip link set $veth1 up

    ip netns add ns0
    ip link set $veth2 netns ns0
    ip netns exec ns0 ip addr add $ip2/24 dev $veth2
    ip netns exec ns0 ip link set $veth2 up
    tc qdisc add dev $veth1 ingress
}

function cleanup_veth() {
    local veth1=$1
    local veth2=$2

    ip netns del ns0 2> /dev/null
    ip link del $veth1 &> /dev/null
    ip link del $veth2 &> /dev/null
}

function cleanup_exit() {
    cleanup_iperf
    cleanup_veth $VETH0 $VETH1
}
trap cleanup_exit EXIT

function run_iperf_server() {
    local port=$1

    ip netns exec ns0 iperf3 -s -p $port &>/dev/null &
}

function run_iperf_client() {
    local ip=$1
    local port=$2
    local rate=$3
    local time=$4

    title "Test iperf veth0 <- veth1($ip : $port)"
    iperf3 -c $ip -u -b $rate -R -l 16 -t $time -p $port &>/dev/null &
}

function spawn_n_iperf_pairs() {
    local ip=$1
    local port_start=$2
    local rate=$3
    local time=$4
    local n_pairs=$5
    local port_end=$((port_start+n_pairs-1))

    for port in $(seq $port_start $port_end); do
        run_iperf_server $port
    done

    # wait for iperf servers to start
    sleep 1

    for port in $(seq $port_start $port_end); do
        run_iperf_client $IP2 $port $rate $time
    done

    #wait for clients to establish connections and start traffic
    sleep 1
}

function cleanup_iperf() {
    exec 3>&2
    exec 2> /dev/null
    killall -q -9 iperf3
    ip netns exec ns0 killall -q -9 iperf3
    sleep 0.1
    exec 2>&3
    exec 3>&-
}

function add_drop_rule() {
    local dev=$1
    local chain=$2
    local prio=$3
    local handle=$4
    local ip=$5
    local port=$6

    tc_filter add dev $dev protocol ip ingress chain $chain prio $prio handle $handle flower skip_hw dst_ip $ip ip_proto udp src_port $port action gact drop
}

function del_drop_rule() {
    local dev=$1
    local chain=$2
    local prio=$3
    local handle=$4

    tc_filter del dev $dev protocol ip ingress chain $chain prio $prio handle $handle flower
}

function check_num_filters() {
    local dev=$1
    local num_filters=$2
    local res="tc -s filter show dev $dev ingress | grep not_in_hw"

    RES=`eval $res | wc -l`
    if (( RES != $num_filters )); then err "Got $RES filters, expected $num_filters filters"; fi
}

function check_filters_traffic() {
    local dev=$1
    local num_filters=$2

    check_num_filters $dev $num_filters

    for sent in $(tc -s filter show dev $dev ingress | grep -Eo 'Sent [0-9]+' | cut -d " " -f 2); do
        if (( $sent == 0 ))
        then
            err "Zero packets on filter"
            break
        fi
    done
}
