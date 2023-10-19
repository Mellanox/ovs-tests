#!/bin/bash
#
# Test traffic VM to external with DVR (external gateway same as host) over vlan
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-osp-test.sh

require_interfaces NIC
require_remote_server

read_osp_topology_vm_ext $PF_VLAN_INT

function clean_up_test() {
    ovn_clean_up
    ovn_remove_network
    on_remote_exec "ip link del $PF_VLAN_INT
                    __reset_nic"
}

function config_test() {
    ovn_single_node_external_config $OVN_LOCAL_CENTRAL_IP $OSP_EXTERNAL_NETWORK
    ovn_lsp_set_tag $SWITCH_EXT_NETWORK_PORT $OVN_VLAN_TAG
    ovn_config_interface_namespace $CLIENT_VF $CLIENT_REP $CLIENT_NS $CLIENT_PORT $CLIENT_MAC $CLIENT_IPV4 $CLIENT_IPV6 $CLIENT_GATEWAY_IPV4 $CLIENT_GATEWAY_IPV6

    config_ovn_external_server_ip_vlan
}

function run_test() {
    ovs-vsctl show
    ovn-sbctl show

    run_remote_traffic "icmp6_is_not_offloaded" "icmp4_is_not_offloaded" $SERVER_PORT
}

TRAFFIC_INFO['server_ns']=""
TRAFFIC_INFO['server_verify_offload']=""

clean_up_test
trap clean_up_test EXIT

config_test
run_test

trap - EXIT
clean_up_test

test_done
