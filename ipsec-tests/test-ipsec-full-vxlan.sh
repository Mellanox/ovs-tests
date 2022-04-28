#!/bin/bash

# This test configures ipsec with vxlan
# and verifies that it has traffic.

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh
. $my_dir/common-ipsec-offload.sh

require_remote_server

vxlan_lip="1.1.1.1"
vxlan_rip="1.1.1.2"

function config_vxlan_local() {
    ip link add vx0 type vxlan id 100 local $LIP remote $RIP dev $NIC dstport 4789
    ifconfig vx0 $vxlan_lip/24 up
}

function config_vxlan_remote() {
    on_remote "ip link add vx0 type vxlan id 100 local $RIP remote $LIP dev $REMOTE_NIC dstport 4789
               ifconfig vx0 $vxlan_rip/24 up"
}

function config() {
    local mtu=$1
    title "configure IPsec in transport mode with 128 key length using ipv4 over a vxlan tunnel with $mtu MTU"
    change_mtu_on_both_sides $mtu
    ipsec_set_mode full
    ipsec_set_mode_on_remote full
    ipsec_config_on_both_sides transport 128 ipv4 full_offload
    config_vxlan_local
    config_vxlan_remote
}

function cleanup() {
    ip link del dev vx0 2> /dev/null
    on_remote "ip link del dev vx0 2> /dev/null"
    cleanup_full
}

function run_test() {
    title "Run traffic"
    local t=5
    start_iperf_server

    local remote_pre_test_pkts_tx=`get_ipsec_counter_on_remote tx`
    local remote_pre_test_pkts_rx=`get_ipsec_counter_on_remote rx`
    local local_pre_test_pkts_tx=`get_ipsec_counter tx`
    local local_pre_test_pkts_rx=`get_ipsec_counter rx`

    timeout $((t+2)) tcpdump -qnnei $NIC -c 5 -w $TCPDUMP_FILE &
    local pid=$!
    (on_remote timeout $((t+2)) iperf3 -c $vxlan_lip -t $t -i 5) || err "iperf3 failed"

    fail_if_err

    local remote_post_test_pkts_tx=`get_ipsec_counter_on_remote tx`
    local remote_post_test_pkts_rx=`get_ipsec_counter_on_remote rx`
    local local_post_test_pkts_tx=`get_ipsec_counter tx`
    local local_post_test_pkts_rx=`get_ipsec_counter rx`

    sleep 2

    title "Verify traffic on $NIC"
    verify_have_traffic $pid

    if [[ "$remote_post_test_pkts_tx" -le "$remote_pre_test_pkts_tx" || "$remote_post_test_pkts_rx" -le "$remote_pre_test_pkts_rx" ]]; then
            fail "IPsec full offload counters didn't increase on TX side"
    fi
    #verify RX side
    if [[ "$local_post_test_pkts_tx" -le "$local_pre_test_pkts_tx" || "$local_post_test_pkts_rx" -le "$local_pre_test_pkts_rx" ]]; then
            fail "IPsec full offload counters didn't increase on RX side"
    fi
}

trap cleanup EXIT
config 1500
run_test
cleanup
config 9000
run_test
trap - EXIT
cleanup
test_done
