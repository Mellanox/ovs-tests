#!/bin/bash
#
# Test OVS DPDK CT ipv6
#
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh


LOCAL_IP="2001:db8:0:f101::1"
IP2="2001:db8:0:f101::2"
IPV41="8.8.8.1"
IPV42="8.8.8.2"


function cleanup(){
    ovs_cleanup_hw_offload_ct_ipv6
    cleanup_test
}
trap cleanup EXIT

function config() {
    enable_switchdev
    require_interfaces REP REP2 NIC
    unbind_vfs
    bind_vfs
    cleanup_test
    ovs_enable_hw_offload_ct_ipv6
    config_simple_bridge_with_rep 2
    start_vdpa_vm
    start_vdpa_vm $NESTED_VM_NAME2 $NESTED_VM_IP2
    config_ns ns0 $VF $IPV41 $LOCAL_IP
    config_ns ns1 $VF2 $IPV42 $IP2
    # Need to sleep 3 seconds at least for ipv6 address to be added
    sleep 3
}

function run() {
    config
    ovs_add_ct_rules br-phy ip6
    title "Sending icmp"
    verify_ping $LOCAL_IP ns1
    # traffic
    title "Sending traffic"
    generate_traffic "local" $LOCAL_IP ns1
}

run
trap - EXIT
cleanup
test_done
