#!/bin/bash
#
# Test set cpu affinity for each sf.
# Check that the set cpu for sf is as requested.
# Run traffic and check offload between sfs.
#
# required mlxconfig is PER_PF_NUM_SF=1 PF_TOTAL_SF=236 PF_SF_BAR_SIZE=11
# Feature Request #2443426: support dedicated/shared irqs per sf - phase 2 - using devlink

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    deconfig_test
    remove_sfs
}

trap cleanup EXIT

function config() {
    title "Config"
    start_clean_openvswitch
    create_sfs 2

    title "SFs Netdev Rep Info"
    SF1=`sf_get_netdev 1`
    SF_REP1=`sf_get_rep 1`
    SF_DEV1=`sf_get_dev 1`
    echo "SF: $SF1, REP: $SF_REP1, DEV: $SF_DEV1"
    SF2=`sf_get_netdev 2`
    SF_REP2=`sf_get_rep 2`
    SF_DEV2=`sf_get_dev 2`
    echo "SF: $SF2, REP: $SF_REP2, DEV: $SF_DEV2"
}

function config_test() {
    config_vf ns0 $SF1 $SF_REP1 $IP1
    config_vf ns1 $SF2 $SF_REP2 $IP2
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $SF_REP1
    ovs-vsctl add-port br-ovs $SF_REP2
}

function deconfig_test() {
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

function test_same_cpu_affinity() {
    local cpus=$1
    title "Checking sfs cpu affinity with $cpus CPUs"
    config

    sf_set_cpu_affinity $SF_DEV1 $cpus
    sf_set_cpu_affinity $SF_DEV2 $cpus

    config_test
    run_traffic
    cleanup
}

function test_diff_cpu_affinity() {
    local sf0_cpus=$1
    local sf1_cpus=$2
    title "Checking first sf cpu affinity with $sf0_cpus CPUs and second sf cpu affinity with $sf1_cpus CPUs"
    config

    sf_set_cpu_affinity $SF_DEV1 $sf0_cpus
    sf_set_cpu_affinity $SF_DEV2 $sf1_cpus

    config_test
    run_traffic
    cleanup
}

function run() {
    title "Test Setting same CPU affinity for all SFs"
    test_same_cpu_affinity 0
    test_same_cpu_affinity 4-7
    test_same_cpu_affinity 2-5,7

    title "Test Setting different CPU affinity for different SFs"
    test_diff_cpu_affinity 0 1
    test_diff_cpu_affinity 4-7 0-3
}

enbale_irq_reguest_debug
run
disable_irq_reguest_debug
trap - EXIT
test_done
