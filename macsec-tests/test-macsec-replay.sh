#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/macsec-common.sh

require_remote_server

function config() {
    local client_pn=5000
    local server_pn=1000
    local window_size=32
    
    config_macsec_env
    config_keys_and_ips ipv4 ipv4 128
    config_macsec --device $NIC --offload --replay on --window $window_size --pn $client_pn --tx-key $EFFECTIVE_KEY_IN \
                  --rx-key $EFFECTIVE_KEY_OUT --dev-ip "$EFFECTIVE_LIP" --macsec-ip $MACSEC_EFFECTIVE_LIP
    config_macsec_remote --device $NIC --offload --replay on --window $window_size --pn $server_pn --tx-key $EFFECTIVE_KEY_OUT \
                         --rx-key $EFFECTIVE_KEY_IN --dev-ip $EFFECTIVE_RIP --macsec-ip $MACSEC_EFFECTIVE_RIP
}

function cleanup() {
    macsec_cleanup
}

function run_test() {
    local dev=$NIC
    local macsec_dev="macsec0"
    local mtu=1500

    change_mtu_on_both_sides $mtu $dev $macsec_dev
    read_pre_test_counters local
    start_iperf_server
    run_traffic ipv4 icmp $macsec_dev no_traffic
    read_post_test_counters local

    title "Verify Replay"
    if [[ $LOCAL_POST_TEST_PKTS_RX_DROP -le $LOCAL_PRE_TEST_PKTS_RX_DROP ]]; then
        fail "Macsec offload drop counters didn't increase as expected"
    fi

    kill_iperf
}

trap cleanup EXIT
cleanup
config
run_test
trap - EXIT
cleanup
test_done
