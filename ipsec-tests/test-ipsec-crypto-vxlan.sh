#!/bin/bash

# This test configures ipsec with vxlan
# and verifies that it has traffic.

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh
. $my_dir/common-ipsec-crypto.sh

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
    ipsec_config_on_both_sides transport 128 ipv4 offload
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
}

trap cleanup EXIT
config
run_test
cleanup
change_mtu_on_both_sides 9000
config
run_test
trap - EXIT
cleanup
test_done
