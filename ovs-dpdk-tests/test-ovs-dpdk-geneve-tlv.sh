#!/bin/bash
#
# Test OVS-DPDK with geneve traffic
# while having TLV option
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
GENEVE_ID=42

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    set_e2e_cache_enable false
    debug "Restarting OVS"
    start_clean_openvswitch

    config_tunnel "geneve"
    config_local_tunnel_ip $LOCAL_TUN br-phy
}

function config_remote() {
    local geneve_opts="geneve_opts ffff:80:00001234"
    on_remote ip link del $TUNNEL_DEV &>/dev/null
    on_remote ip l del vm &> /dev/null
    on_remote ip link add $TUNNEL_DEV type geneve dstport 6081 external
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip l set dev $TUNNEL_DEV up
    on_remote ip l set dev $REMOTE_NIC up
    on_remote tc qdisc add dev $TUNNEL_DEV ingress

    title "Setup remote geneve + opts"
    on_remote ip link add vm type veth peer name vm_rep
    on_remote ifconfig vm $REMOTE/24 up
    on_remote ifconfig vm_rep 0 promisc up
    on_remote tc qdisc add dev vm_rep ingress
    on_remote tc filter add dev vm_rep ingress proto ip flower skip_hw action tunnel_key set src_ip 0.0.0.0 dst_ip $LOCAL_TUN id $GENEVE_ID dst_port 6081 $geneve_opts pipe action mirred egress redirect dev $TUNNEL_DEV
    on_remote tc filter add dev vm_rep ingress proto arp flower skip_hw action tunnel_key set src_ip 0.0.0.0 dst_ip $LOCAL_TUN id $GENEVE_ID dst_port 6081 $geneve_opts pipe action mirred egress redirect dev $TUNNEL_DEV
    on_remote tc filter add dev $TUNNEL_DEV ingress protocol arp flower skip_hw action tunnel_key unset action mirred egress redirect dev vm_rep
    on_remote tc filter add dev $TUNNEL_DEV ingress protocol ip flower skip_hw action tunnel_key unset action mirred egress redirect dev vm_rep
}

function config_openflow_rules() {
    ovs-ofctl add-tlv-map br-int "{class=0xffff,type=0x80,len=4}->tun_metadata0"
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int arp,actions=normal
    ovs-ofctl add-flow br-int "priority=1,arp,actions=normal"
    ovs-ofctl add-flow br-int "in_port=rep0,actions=set_field:0x1234->tun_metadata0,normal"
    ovs-ofctl add-flow br-int "tun_metadata0=0x1234,actions=normal"
    ovs-ofctl dump-flows br-int --color
}

function run() {
    config
    config_remote
    config_openflow_rules

    verify_ping $REMOTE ns0

    generate_traffic "remote" $IP

    # check offloads
    check_dpdk_offloads $IP
    on_remote ip l del vm &> /dev/null
}

run
start_clean_openvswitch
test_done
