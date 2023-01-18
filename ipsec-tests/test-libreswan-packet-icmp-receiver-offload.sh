#!/bin/bash
#

my_dir="$(dirname "$0")"
. $my_dir/common-libreswan.sh

require_remote_server

function cleanup() {
    ipsec_clear_setup
    cleanup_crypto
}

function config() {
    enable_legacy
    on_remote_exec enable_legacy
}

function run_test() {
    ipsec_config_setup "packet" "no-offload"

    local local_pre_tx=`get_ipsec_counter tx`
    local local_pre_rx=`get_ipsec_counter rx`
    run_traffic ipv4 icmp
    local local_post_tx=`get_ipsec_counter tx`
    local local_post_rx=`get_ipsec_counter rx`
    check_full_offload_counters $local_pre_tx $local_pre_rx $local_post_tx $local_post_rx "on RX side"
}

trap cleanup EXIT
cleanup
config
run_test
trap - EXIT
cleanup
test_done
