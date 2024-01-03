#!/bin/bash
#
# Test OVS with vxlan ipv6 inner and outer traffic and force a long match
# to test 3-way split
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup EXIT

function cleanup() {
    cleanup_test
    on_remote_exec "ovs_conf_set hw-offload true
                    cleanup_test"
}

cleanup

pci=`get_pf_pci`
nic=`get_pf_nic $pci`
NIC_MAC=`bf_wrap cat /sys/class/net/$nic/address`
REMOTE_NIC_MAC=`on_remote cat /sys/class/net/$REMOTE_NIC/address`
VF_MAC=$(cat /sys/class/net/$VF/address)
REMOTE_MAC=`on_remote cat /sys/class/net/$VF/address`

function add_openflow_rules() {
    debug "Adding openflow rules including a long match vxlan tunnel rule"
    ovs-ofctl -O openflow15 del-flows br-int
    ovs-ofctl -O openflow15 add-flow br-int "arp,actions=normal"
    ovs-ofctl -O openflow15 add-flow br-int "icmp,actions=normal"
    ovs-ofctl -O openflow15 add-flow br-int "table=0,in_port=vxlan_br-int,tun_eth_src=$REMOTE_NIC_MAC,tun_eth_dst=$NIC_MAC,dl_src=$REMOTE_MAC,dl_dst=$VF_MAC,icmp6,ipv6_dst=$LOCAL_IPV6/24,ipv6_src=$REMOTE_IPV6/24,actions=$IB_PF0_PORT0"
    ovs-ofctl -O openflow15 add-flow br-int "table=0,in_port=$IB_PF0_PORT0,icmp6,actions=vxlan_br-int"
    ovs-ofctl -O openflow15 dump-flows br-int --color
}

function config() {
    config_tunnel "vxlan" 1 br-phy br-int $TUNNEL_ID $LOCAL_IPV6 $IPV6_REMOTE_TUNNEL_IP
    config_local_tunnel_ip $IPV6_LOCAL_TUNNEL_IP br-phy 112
    ip netns exec ns0 ip -6 neigh add $REMOTE_IPV6 lladdr $REMOTE_MAC dev $VF

    on_remote_exec "start_clean_openvswitch
                    ovs_conf_set hw-offload false
                    config_tunnel vxlan 1 br-phy br-int $TUNNEL_ID $REMOTE_IPV6 $IPV6_LOCAL_TUNNEL_IP
                    config_local_tunnel_ip $IPV6_REMOTE_TUNNEL_IP br-phy 112
                    ip netns exec ns0 ip -6 neigh add $LOCAL_IPV6 lladdr $VF_MAC dev $VF"

    add_openflow_rules
}

function check_offloads() {
    local rules=`ovs-appctl dpctl/dump-flows -m type=offloaded | grep "$REMOTE_IPV6\|tnl_pop" | wc -l`
    local pkts_in_sw=`get_total_packets_passed_in_sw`

    if [ $rules -ne 3 ]; then
        err "Offloads failed, expected 3 offloaded rules but got $rules"
    fi

    if [ $pkts_in_sw -gt 500 ]; then
        err "Expected at most 500 packets in sw but got $pkts_in_sw"
    fi
    success2 "$pkts_in_sw packets passed in sw"
    success2 "Found $rules offloaded rules"
}

function run() {
    config

    # icmp
    verify_ping $REMOTE_IPV6 ns0 56 1000 0.01 80

    check_offloads
}

run
trap - EXIT
cleanup
test_done
