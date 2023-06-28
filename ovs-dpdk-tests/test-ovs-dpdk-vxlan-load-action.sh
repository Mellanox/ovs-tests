#!/bin/bash
#
# Test OVS with vxlan traffic
#
# Bug SW #2247261: OVS-DPDK: encap rule cannot be offloaded
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs

DUMMY_MAC=00:00:0a:e3:c4:01
VF_MAC=$(cat /sys/class/net/$VF/address)

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev vxlan1 &>/dev/null
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    cleanup_e2e_cache
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 0
    config_remote_bridge_tunnel $TUNNEL_ID $REMOTE_TUNNEL_IP
    config_remote_tunnel "vxlan"
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
    config_ns ns0 $VF $LOCAL_IP
}

function add_openflow_rules() {
    VXLAN_MAC=$(on_remote cat /sys/class/net/$TUNNEL_DEV/address)
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int "arp,actions=NORMAL"
    ovs-ofctl add-flow br-int "table=0, idle_age=0, priority=200,tun_id=$TUNNNEL_ID,in_port=vxlan0 actions=load:0x1->OXM_OF_METADATA[],resubmit(,100)"
    ovs-ofctl add-flow br-int "table=0, priority=100,idle_age=0,in_port=rep0 actions=load:0x4f6->NXM_NX_REG6[],load:0x1->OXM_OF_METADATA[],load:0->OXM_OF_IN_PORT[],resubmit(,0)"
    ovs-ofctl add-flow br-int "table=0, priority=1,idle_age=0,actions=resubmit(,5)"
    ovs-ofctl add-flow br-int "table=5, priority=1,idle_age=0,actions=resubmit(,10)"
    ovs-ofctl add-flow br-int "table=10, priority=1,idle_age=0,actions=resubmit(,17)"
    ovs-ofctl add-flow br-int "table=17, priority=1,idle_age=0,actions=resubmit(,20)"
    ovs-ofctl add-flow br-int "table=20, priority=1,idle_age=0,actions=resubmit(,55)"
    ovs-ofctl add-flow br-int "table=55, priority=200,idle_age=0,metadata=0x1,dl_dst=$VXLAN_MAC actions=resubmit(,60)"
    ovs-ofctl add-flow br-int "table=60, priority=200,idle_age=0,ip,metadata=0x1,nw_dst=$REMOTE_IP actions=mod_dl_src:$DUMMY_MAC,resubmit(,65)"
    ovs-ofctl add-flow br-int "table=65, priority=200,idle_age=0,ip,metadata=0x1,nw_dst=$REMOTE_IP actions=mod_dl_dst:$VXLAN_MAC,load:0x5b2->NXM_NX_REG7[],resubmit(,75)"
    ovs-ofctl add-flow br-int "table=75, priority=100,idle_age=0,reg7=0x5b2 actions=load:0->OXM_OF_IN_PORT[],load:0xaca80102->NXM_NX_TUN_IPV4_DST[],load:0x64->NXM_NX_TUN_ID[],output:vxlan0"
    ovs-ofctl add-flow br-int "table=100, idle_age=0, priority=200,metadata=0x1,dl_dst=$VF_MAC actions=load:0x4f6->NXM_NX_REG7[],resubmit(,105)"
    ovs-ofctl add-flow br-int "table=105, idle_age=0, priority=1 actions=resubmit(,112)"
    ovs-ofctl add-flow br-int "table=112, idle_age=0, priority=1 actions=resubmit(,114)"
    ovs-ofctl add-flow br-int "table=114, idle_age=0, priority=1 actions=resubmit(,115)"
    ovs-ofctl add-flow br-int "table=115, idle_age=0, priority=100,reg7=0x4f6 actions=output:rep0"

    ovs-ofctl dump-flows br-int --color
}

function run() {
    config
    add_openflow_rules

    # icmp
    verify_ping $REMOTE_IP ns0

    sleep 1
    # check offloads
    check_dpdk_offloads $LOCAL_IP
}

run
start_clean_openvswitch
test_done
