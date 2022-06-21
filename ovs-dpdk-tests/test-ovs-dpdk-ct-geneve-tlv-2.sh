#!/bin/bash
#
# Test OVS-DPDK with geneve traffic
# while having TLV options having OVS-DPDK on both sides to cover
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
    local cmd="ovs-ofctl del-flows br-int; \
    ovs-ofctl add-flow br-int arp,actions=normal; \
    ovs-ofctl add-flow br-int icmp,actions=normal; \
    ovs-ofctl add-tlv-map br-int \"{class=0xffff,type=0x80,len=4}->tun_metadata0\"; \
    ovs-ofctl add-flow br-int \"table=0,in_port=geneve0,ip,tun_metadata0=0x1234,ct_state=-trk actions=ct(table=1)\"; \
    ovs-ofctl add-flow br-int \"table=1,in_port=geneve0,ip,tun_metadata0=0x1234,ct_state=+trk+new actions=ct(commit),normal\"; \
    ovs-ofctl add-flow br-int \"table=1,in_port=geneve0,ip,tun_metadata0=0x1234,ct_state=+trk+est actions=normal\"; \
    ovs-ofctl add-flow br-int \"table=0,in_port=rep0,ip,ct_state=-trk actions=ct(table=1)\"; \
    ovs-ofctl add-flow br-int \"table=1,in_port=rep0,ip,ct_state=+trk+new actions=set_field:0x1234->tun_metadata0,ct(commit),normal\"; \
    ovs-ofctl add-flow br-int \"table=1,in_port=rep0,ip,ct_state=+trk+est actions=set_field:0x1234->tun_metadata0,normal\"; \
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
