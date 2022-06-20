#!/bin/bash
#
# Test OVS-DPDK with geneve traffic
# while having TLV option having OVS-DPDK on both sides to cover
# cases which geneve tunnel is not supported by kernel
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

require_remote_server

cleanup_test
remote_ovs_cleanup

function config_openflow_rules() {
    local exec_on_remote=${1:-false}
    local cmd="ovs-ofctl add-tlv-map br-int \"{class=0xffff,type=0x80,len=4}->tun_metadata0\"; \
               ovs-ofctl del-flows br-int; \
               ovs-ofctl add-flow br-int arp,actions=normal; \
               ovs-ofctl add-flow br-int \"priority=1,arp,actions=normal\"; \
               ovs-ofctl add-flow br-int \"in_port=rep0,actions=set_field:0x1234->tun_metadata0,normal\"; \
               ovs-ofctl add-flow br-int \"tun_metadata0=0x1234,actions=normal\"; \
               ovs-ofctl dump-flows br-int --color; \
               "

    if [ "$exec_on_remote" = true ]; then
        on_remote_dt "$cmd"
    else
        eval "$cmd"
    fi
}

function run() {
    config_2_side_tunnel geneve
    config_openflow_rules false
    config_openflow_rules true

    verify_ping

    generate_traffic "remote" $LOCAL_IP ns0
    # check offloads
    check_dpdk_offloads $LOCAL_IP
}

run
cleanup_test
remote_ovs_cleanup
test_done
