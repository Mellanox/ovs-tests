#!/bin/bash
#
# Test OVS with vxlan traffic
#
# Bug SW #2247261: OVS-DPDK: encap rule cannot be offloaded
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

require_remote_server

IP=192.168.10.2
REMOTE=192.168.10.3

LOCAL_TUN=172.168.1.1
REMOTE_IP=172.168.1.2
VXLAN_ID=100

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
    set_e2e_cache_enable false
    debug "Restarting OVS"
    start_clean_openvswitch

    config_simple_bridge_with_rep 0
    config_remote_bridge_tunnel $VXLAN_ID $REMOTE_IP
    config_local_tunnel_ip $LOCAL_TUN br-phy
    config_ns ns0 $VF $IP
}

function config_remote() {
    on_remote ip link del vxlan1 &>/dev/null
    on_remote ip link add vxlan1 type vxlan id $VXLAN_ID remote $LOCAL_TUN dstport 4789
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip a add $REMOTE/24 dev vxlan1
    on_remote ip l set dev vxlan1 up
    VXLAN_MAC=$(on_remote cat /sys/class/net/vxlan1/address)
    on_remote ip l set dev $REMOTE_NIC up
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int "arp,actions=NORMAL"
    ovs-ofctl add-flow br-int "table=0, idle_age=0, priority=200,tun_id=0x64,in_port=vxlan0 actions=load:0x1->OXM_OF_METADATA[],resubmit(,100)"
    ovs-ofctl add-flow br-int "table=0, priority=100,idle_age=0,in_port=rep0 actions=load:0x4f6->NXM_NX_REG6[],load:0x1->OXM_OF_METADATA[],load:0->OXM_OF_IN_PORT[],resubmit(,0)"
    ovs-ofctl add-flow br-int "table=0, priority=1,idle_age=0,actions=resubmit(,5)"
    ovs-ofctl add-flow br-int "table=5, priority=1,idle_age=0,actions=resubmit(,10)"
    ovs-ofctl add-flow br-int "table=10, priority=1,idle_age=0,actions=resubmit(,17)"
    ovs-ofctl add-flow br-int "table=17, priority=1,idle_age=0,actions=resubmit(,20)"
    ovs-ofctl add-flow br-int "table=20, priority=1,idle_age=0,actions=resubmit(,55)"
    ovs-ofctl add-flow br-int "table=55, priority=200,idle_age=0,metadata=0x1,dl_dst=$VXLAN_MAC actions=resubmit(,60)"
    ovs-ofctl add-flow br-int "table=60, priority=200,idle_age=0,ip,metadata=0x1,nw_dst=$REMOTE actions=mod_dl_src:$DUMMY_MAC,resubmit(,65)"
    ovs-ofctl add-flow br-int "table=65, priority=200,idle_age=0,ip,metadata=0x1,nw_dst=$REMOTE actions=mod_dl_dst:$VXLAN_MAC,load:0x5b2->NXM_NX_REG7[],resubmit(,75)"
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
    config_remote
    add_openflow_rules

    # icmp
    ip netns exec ns0 ping -q -c 10 -w 15 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    sleep 1
    # check offloads
    check_dpdk_offloads $IP
}

run
start_clean_openvswitch
test_done
