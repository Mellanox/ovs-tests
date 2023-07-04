#!/bin/bash
#
# Test OVS-DPDK with CT using
# Geneve tunnel with TLV options
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
require_interfaces REP NIC
unbind_vfs
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    config_tunnel geneve 1
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
}

function config_remote() {
    local geneve_opts="geneve_opts ffff:80:00001234"
    on_remote ip link del $TUNNEL_DEV &>/dev/null
    on_remote ip l del vm &> /dev/null
    on_remote ip link add $TUNNEL_DEV type geneve dstport 6081 external
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_TUNNEL_IP/24 dev $REMOTE_NIC
    on_remote ip l set dev $TUNNEL_DEV up
    on_remote ip l set dev $REMOTE_NIC up
    on_remote tc qdisc add dev $TUNNEL_DEV ingress

    title "Setup remote geneve + opts"
    on_remote ip link add vm type veth peer name vm_rep
    on_remote ifconfig vm $REMOTE_IP/24 up
    on_remote ifconfig vm_rep 0 promisc up
    on_remote tc qdisc add dev vm_rep ingress
    on_remote tc filter add dev vm_rep ingress proto ip flower skip_hw action tunnel_key set src_ip 0.0.0.0 dst_ip $LOCAL_TUN_IP id $TUNNEL_ID dst_port 6081 $geneve_opts pipe action mirred egress redirect dev $TUNNEL_DEV
    on_remote tc filter add dev vm_rep ingress proto arp flower skip_hw action tunnel_key set src_ip 0.0.0.0 dst_ip $LOCAL_TUN_IP id $TUNNEL_ID dst_port 6081 $geneve_opts pipe action mirred egress redirect dev $TUNNEL_DEV
    on_remote tc filter add dev $TUNNEL_DEV ingress protocol arp flower skip_hw action tunnel_key unset action mirred egress redirect dev vm_rep
    on_remote tc filter add dev $TUNNEL_DEV ingress protocol ip flower skip_hw action tunnel_key unset action mirred egress redirect dev vm_rep
}

function config_openflow_rules() {
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int arp,actions=normal
    ovs-ofctl add-flow br-int icmp,actions=normal
    ovs-ofctl add-tlv-map br-int "{class=0xffff,type=0x80,len=4}->tun_metadata0"
    ovs-ofctl add-flow br-int "table=0,in_port=geneve_br-int,ip,tun_metadata0=0x1234,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-int "table=1,in_port=geneve_br-int,ip,tun_metadata0=0x1234,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-int "table=1,in_port=geneve_br-int,ip,tun_metadata0=0x1234,ct_state=+trk+est actions=normal"
    ovs-ofctl add-flow br-int "table=0,in_port=$IB_PF0_PORT0,ip,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-int "table=1,in_port=$IB_PF0_PORT0,ip,ct_state=+trk+new actions=set_field:0x1234->tun_metadata0,ct(commit),normal"
    ovs-ofctl add-flow br-int "table=1,in_port=$IB_PF0_PORT0,ip,ct_state=+trk+est actions=set_field:0x1234->tun_metadata0,normal"
    ovs-ofctl dump-flows br-int --color
}

function run() {
    config
    config_remote
    config_openflow_rules

    verify_ping $REMOTE_IP ns0

    generate_traffic "remote" $LOCAL_IP

    on_remote ip l del vm &> /dev/null
}

run
trap - EXIT
cleanup_test
test_done
