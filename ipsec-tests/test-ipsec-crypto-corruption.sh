#!/bin/bash

# This test sends corrupted packets (by changing the
# sequence number in the ESP header.
# expected result: to have no traffic

my_dir="$(dirname "$0")"
. $my_dir/common-ipsec.sh

require_remote_server

PCAP_FILE="/tmp/corruption-test-pkts.pcap"


function config() {
    cleanup
    ipsec_config_on_both_sides transport 128 ipv4 offload
}

function cleanup() {
    cleanup_crypto
    rm -f $PCAP_FILE
}

function prep_pcap() {
    title "Prepare pcap file"
    local t=10
    start_iperf_server_on_remote
    timeout $((t+2)) tcpdump -n -s0 -p -i $NIC -c 5 -Q out -w $PCAP_FILE esp or udp port 4500 &
    sleep 1
    timeout $((t+2)) timeout $((t+2)) iperf3 -c $RIP -t $t || err "iperf3 failed"
    fail_if_err
    sleep 1
}

function run_test() {
    prep_pcap
    local t=10
    local init_pkts=`on_remote ethtool -S $REMOTE_NIC | grep -E 'rx_packets_phy|vport_rx_packets' | awk {'print $2'} | tail -1`

    title "Send corrupted packets"
    on_remote timeout $((t+2)) tcpdump -qnnei $REMOTE_NIC -c 5 &
    local pid=$!
    python $my_dir/corrupt-auth.py $NIC
    local curr_pkts=`on_remote ethtool -S $REMOTE_NIC | grep -E 'rx_packets_phy|vport_rx_packets' | awk {'print $2'} | tail -1`

    title "Verify no traffic on $REMOTE_NIC"
    if [[ "$init_pkts" == "$curr_pkts" ]];then
        fail "Corrupted packets are not getting to destination"
    fi
    verify_no_traffic $pid
}

trap cleanup EXIT
config
run_test
trap - EXIT
cleanup
test_done
