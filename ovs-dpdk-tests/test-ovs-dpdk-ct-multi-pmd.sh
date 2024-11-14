#!/bin/bash
#
# Test OVS-DPDK TCP traffic with CT and OVS configured with multi PMD
#
# Require external server
#
# Bug SW #4069266: [OVS-DOCA, Performance] Failed to insert DOCA-CT entry: -24 when sending 20 mpps rate with packet size 114 and ct connections
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup EXIT

#total connections (conns) must be multiple of 512
test_total_conns=4096
test_iperf_conns=128
test_iperf_start_port=5201
test_iperf_conn_bandwitdh="500k"
test_iperf_run_time=20

function cleanup() {
    stop_traffic
    ovs-vsctl --no-wait remove o . other_config pmd-cpu-mask
    ovs-vsctl --no-wait remove o . other_config hw-offload-ct-size
    ovs-vsctl --no-wait remove o . other_config doca-ct
    ovs-vsctl --no-wait remove o . other_config doca-ct-ipv6
    cleanup_test
}

function config() {
    config_simple_bridge_with_rep 1
    config_ns ns0 $VF $LOCAL_IP
    ovs-vsctl --timeout=$OVS_VSCTL_TIMEOUT set o . other_config:doca-ct=true
    ovs-vsctl --timeout=$OVS_VSCTL_TIMEOUT set o . other_config:doca-ct-ipv6=false
    ovs-vsctl --timeout=$OVS_VSCTL_TIMEOUT set o . other_config:pmd-cpu-mask=0x6
    ovs-vsctl --timeout=$OVS_VSCTL_TIMEOUT set o . other_config:hw-offload-ct-size=$test_total_conns
    restart_openvswitch_nocheck
}

function add_openflow_rules() {
    ovs_add_ct_rules br-phy tcp
}

function multi_iperf3_server() {
    local i

    for i in `seq 1 $(((test_total_conns/test_iperf_conns)))`; do
        iperf3 -D -s -i 0 -p $((test_iperf_start_port+i-1))
    done
}

function multi_iperf3_client() {
    local i

    for i in `seq 1 $(((test_total_conns/test_iperf_conns)))`; do
         ip netns exec ns0 iperf3 -c $REMOTE_IP -i 0 -p $((test_iperf_start_port+i-1)) -P $((test_iperf_conns-1)) -b $test_iperf_conn_bandwitdh -t $test_iperf_run_time > /tmp/iperf3_c_$i &
    done
}

function multi_iperf3() {
    on_remote_exec multi_iperf3_server
    multi_iperf3_client &
}

function run() {
    local reached=false
    local i

    config
    config_remote_nic
    add_openflow_rules

    verify_ping

    title "Run traffic and try to fill ct table entirely"
    multi_iperf3

    title "Wait for traffic"
    for i in `seq 1 $((test_iperf_run_time+10))`; do
        local conns=`ovs-appctl dpctl/offload-stats-show | grep -i -o "Total.*CT bi-dir Conn.*"`
        echo $conns

        $reached || { echo $conns | grep -q $test_total_conns && success "Reached $test_total_conns connections" && reached=true; }

        $reached && echo $conns | grep -q -P "Connections:\s+0" && break

        sleep 1
    done

    $reached || err "Failed to reach $test_total_conns connections"
}

run

check_counters

trap - EXIT
cleanup
test_done
