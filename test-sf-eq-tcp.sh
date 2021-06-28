#!/bin/bash
#
# Test SF EQ memory optimizations while changing the eq configuration and running tcp connection.
#
# required mlxconfig is PF_BAR2_SIZE=3 PF_BAR2_ENABLE=1
# [MKT. BlueField-SW] Feature Request #2482519: EQ memory optimizations - OFED first
# [MLNX OFED] Bug SW #2248656: [MLNX OFED SF] Creating SF is causing a kfree for unknown address

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir//common-sf-mlxdevm.sh

if ! is_ofed ; then
    fail "This feature is supported only over OFED"
fi

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    start_clean_openvswitch
    remove_sfs
}

trap cleanup EXIT

function remove_ns() {
    ip netns del ns0 &> /dev/null
    ip netns del ns1 &> /dev/null
    ovs_clear_bridges
}

function set_eq_config() {
    title "Configure SFs EQ"
    local max_cmpl_eqs=$1
    local cmpl_eq_depth=$2
    local async_eq_depth=$3

    echo "max_cmpl_eqs: $max_cmpl_eqs"
    echo "cmpl_eq_depth: $cmpl_eq_depth"
    echo "async_eq_depth: $async_eq_depth"

    local i
    for i in 0 1; do
        local sf_dev="${SF_DEVS[$i]}"
        sf_unbind $sf_dev
        sf_cfg_bind $sf_dev
        sleep 1

        sf_set_param $sf_dev max_cmpl_eqs $max_cmpl_eqs
        sf_set_param $sf_dev cmpl_eq_depth $cmpl_eq_depth
        sf_set_param $sf_dev async_eq_depth $async_eq_depth

        sf_cfg_unbind $sf_dev
        sf_bind $sf_dev
        sleep 1
    done

}

function config() {
    title "Config"
    start_clean_openvswitch
    sf_disable_roce=1
    create_sfs 2

    title "SFs Netdev Rep Info"
    SF="${SF_NETDEVS[0]}"
    SF_REP="${SF_REPS[0]}"
    echo "SF: $SF, REP: $SF_REP"
    SF1="${SF_NETDEVS[1]}"
    SF_REP1="${SF_REPS[1]}"
    echo "SF: $SF1, REP: $SF_REP1"
}

function config_ns() {
    config_vf ns0 $SF $SF_REP $IP1
    config_vf ns1 $SF1 $SF_REP1 $IP2
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $SF_REP
    ovs-vsctl add-port br-ovs $SF_REP1
}

function run_traffic() {
    t=15
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -P 3 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $SF_REP"
    timeout $((t-4)) tcpdump -qnnei $SF_REP -c 10 'tcp' &
    pid1=$!

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    title "test traffic offload"
    verify_no_traffic $pid1
}

function run() {
    max_cmpl_eqs=1
    cmpl_eq_depth=256
    async_eq_depth=1024

    local i
    for i in 1 2 3; do
        title "Case $i"
        set_eq_config $(($max_cmpl_eqs * $i)) $(($cmpl_eq_depth * $i)) $(($async_eq_depth * $i))
        config_ns
        run_traffic
        remove_ns
    done
}

config
run
cleanup
trap - EXIT
test_done
