#!/bin/bash

# This test configures ipsec with vxlan
# and verifies that it has traffic.

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

require_remote_server

vxlan_lip="1.1.1.1"
vxlan_rip="1.1.1.2"

function config_vxlan_local() {
    ip link add vx0 type vxlan id 100 local $LIP6 remote $RIP6 dev $NIC dstport 4789
    ifconfig vx0 $vxlan_lip/24 up
}

function config_vxlan_remote() {
    on_remote "ip link add vx0 type vxlan id 100 local $RIP6 remote $LIP6 dev $REMOTE_NIC dstport 4789
               ifconfig vx0 $vxlan_rip/24 up"
}

function verify_crypto_offload_on_both_sides() {
    local tx_off=`on_remote ip x s s | grep offload |wc -l`
    local rx_off=`ip x s s | grep offload |wc -l`
    title "Verify offload"
    if [[ "$tx_off" != 2 || "$rx_off" != 2 ]]; then
        fail "offload rules are not added as expected!"
    fi
}

function config() {
    local mtu=$1
    title "configure IPsec in transport mode with 128 key length using ipv6 over a vxlan tunnel with $mtu MTU"
    change_mtu_on_both_sides $mtu
    ipsec_config_on_both_sides transport 128 ipv6 offload
    config_vxlan_local
    config_vxlan_remote
}

function cleanup() {
    kill_iperf
    ipsec_cleanup_on_both_sides
    ip link del dev vx0 2> /dev/null
    on_remote "ip link del dev vx0 2> /dev/null"
    change_mtu_on_both_sides 1500
    rm -f $TCPDUMP_FILE
}

function run_test() {
    title "Run traffic"
    local t=5
    start_iperf_server

    timeout $((t+2)) tcpdump -qnnei $NIC -c 5 -w $TCPDUMP_FILE &
    local pid=$!
    (on_remote timeout $((t+2)) iperf3 -c $vxlan_lip -t $t -i 5) || err "iperf3 failed"

    fail_if_err

    sleep 2

    title "Verify traffic on $NIC"
    verify_have_traffic $pid
    verify_crypto_offload_on_both_sides
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
