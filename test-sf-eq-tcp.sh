#!/bin/bash
#
# Test SF EQ memory optimizations while changing the eq configuration and running tcp connection.
#
# required OFED is built using --with-sf-cfg-drv
# [MKT. BlueField-SW] Feature Request #2482519: EQ memory optimizations - OFED first
# [MLNX OFED] Bug SW #2248656: [MLNX OFED SF] Creating SF is causing a kfree for unknown address

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

if ! is_ofed ; then
    fail "This feature is supported only over OFED"
fi

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    deconfig_iter
    remove_sfs
}

trap cleanup EXIT

function config() {
    title "Config"
    sf_with_cfg=1
    create_sfs 2
    fail_if_err "Failed to create sfs"

    start_clean_openvswitch

    title "SFs Netdev Rep Info"
    SF1=`sf_get_netdev 1`
    SF_REP1=`sf_get_rep 1`
    echo "SF: $SF1, REP: $SF_REP1"

    SF2=`sf_get_netdev 2`
    SF_REP2=`sf_get_rep 2`
    echo "SF: $SF2, REP: $SF_REP2"
}

function config_iter() {
    config_vf ns0 $SF1 $SF_REP1 $IP1
    config_vf ns1 $SF2 $SF_REP2 $IP2
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $SF_REP1
    ovs-vsctl add-port br-ovs $SF_REP2
}

function deconfig_iter() {
    ip netns del ns0 &> /dev/null
    ip netns del ns1 &> /dev/null
    ovs_clear_bridges
}

function run_traffic() {
    t=15
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -P 3 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $SF_REP1"
    timeout $((t-4)) tcpdump -qnnei $SF_REP1 -c 10 'tcp' &
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
        config_sfs_eq $(($max_cmpl_eqs * $i)) $(($cmpl_eq_depth * $i)) $(($async_eq_depth * $i))
        config_iter
        run_traffic
        deconfig_iter
    done
}

config
run
cleanup
trap - EXIT
test_done
