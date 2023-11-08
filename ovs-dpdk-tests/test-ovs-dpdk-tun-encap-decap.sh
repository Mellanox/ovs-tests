#!/bin/bash
#
# Test OVS with vxlan traffic with explicit tunnel
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

NIC_MAC=`cat /sys/class/net/$NIC/address`
REMOTE_MAC=`on_remote cat /sys/class/net/$NIC/address`
BRIDGE="br-phy"

trap cleanup_test EXIT

function config() {
    local PF=`get_port_from_pci`
    local VXLAN_DEV="vxlan_$BRIDGE"

    cleanup_test

    config_tunnel "vxlan" 1 $BRIDGE $BRIDGE
    ovs-vsctl set interface $VXLAN_DEV options:explicit=true
    restart_openvswitch
    config_remote_tunnel "vxlan"
    on_remote arp -s $LOCAL_TUN_IP $NIC_MAC

    ovs-ofctl del-flows $BRIDGE
    ovs-ofctl add-flow $BRIDGE "in_port=$IB_PF0_PORT0,actions=set_field:$LOCAL_TUN_IP->tun_src,set_field:$REMOTE_TUNNEL_IP->tun_dst,set_field:$TUNNEL_ID->tun_id,set_field:$NIC_MAC->tun_eth_src,set_field:$REMOTE_MAC->tun_eth_dst,tun_encap($VXLAN_DEV),$PF"
    ovs-ofctl add-flow $BRIDGE "in_port=$PF,tun_eth_dst=$NIC_MAC,tun_type=vxlan,actions=tun_decap($VXLAN_DEV),$IB_PF0_PORT0"

    ovs-vsctl show
    ovs-ofctl dump-flows $BRIDGE --color
}

function run() {
    config

    # icmp
    verify_ping $REMOTE_IP ns0

    generate_traffic "remote" $LOCAL_IP
    ovs-appctl dpctl/dump-flows -m
}

run
trap - EXIT
cleanup_test
test_done
