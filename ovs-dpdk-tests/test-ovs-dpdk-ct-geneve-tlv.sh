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
enable_switchdev
require_interfaces REP NIC
bind_vfs

trap cleanup EXIT

function cleanup() {
    on_remote "ip link del $TUNNEL_DEV &>/dev/null
               ip l del vm &> /dev/null
               ip a flush dev $REMOTE_NIC"
    cleanup_test
}

function config() {
    cleanup_test
    config_tunnel geneve 1
    config_local_tunnel_ip $LOCAL_TUN_IP br-phy
}

function config_remote() {
    config_remote_arm_bridge
    local geneve_opts="geneve_opts ffff:80:00001234"
    title "Setup remote geneve + opts"

    on_remote "ip link del $TUNNEL_DEV &>/dev/null
     ip link add $TUNNEL_DEV type geneve dstport 6081 external
     ip a flush dev $REMOTE_NIC
     ip a add $REMOTE_TUNNEL_IP/24 dev $REMOTE_NIC
     ip l set dev $TUNNEL_DEV up
     ip l set dev $REMOTE_NIC up
     ip link set dev $TUNNEL_DEV mtu 1400
     tc qdisc add dev $TUNNEL_DEV ingress"

    on_remote "ip l del vm &> /dev/null
     ip link add vm type veth peer name vm_rep
     ifconfig vm $REMOTE_IP/24 up
     ifconfig vm_rep 0 promisc up
     tc qdisc add dev vm_rep ingress
     tc filter add dev vm_rep ingress proto ip flower skip_hw action tunnel_key set src_ip 0.0.0.0 dst_ip $LOCAL_TUN_IP id $TUNNEL_ID dst_port 6081 $geneve_opts pipe action mirred egress redirect dev $TUNNEL_DEV
     tc filter add dev vm_rep ingress proto arp flower skip_hw action tunnel_key set src_ip 0.0.0.0 dst_ip $LOCAL_TUN_IP id $TUNNEL_ID dst_port 6081 $geneve_opts pipe action mirred egress redirect dev $TUNNEL_DEV
     tc filter add dev $TUNNEL_DEV ingress protocol arp flower skip_hw action tunnel_key unset action mirred egress redirect dev vm_rep
     tc filter add dev $TUNNEL_DEV ingress protocol ip flower skip_hw action tunnel_key unset action mirred egress redirect dev vm_rep"
}

function config_openflow_rules() {
    title "add openflow rules"
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int arp,actions=normal
    ovs-ofctl add-flow br-int icmp,actions=normal
    ovs-ofctl add-tlv-map br-int "{class=0xffff,type=0x80,len=4}->tun_metadata0"
    ovs-ofctl add-flow br-int "table=0,in_port=geneve_br-int,ip,tun_metadata0=0x1234,ct_state=-trk, actions=ct(table=1)"
    ovs-ofctl add-flow br-int "table=1,in_port=geneve_br-int,ip,tun_metadata0=0x1234,ct_state=+trk+new, actions=ct(commit),normal"
    ovs-ofctl add-flow br-int "table=1,in_port=geneve_br-int,ip,tun_metadata0=0x1234,ct_state=+trk+est, actions=normal"
    ovs-ofctl add-flow br-int "table=0,in_port=$IB_PF0_PORT0,ip,ct_state=-trk, actions=ct(table=1)"
    ovs-ofctl add-flow br-int "table=1,in_port=$IB_PF0_PORT0,ip,ct_state=+trk+new, actions=set_field:0x1234->tun_metadata0,ct(commit),normal"
    ovs-ofctl add-flow br-int "table=1,in_port=$IB_PF0_PORT0,ip,ct_state=+trk+est, actions=set_field:0x1234->tun_metadata0,normal"
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

add_expected_error_for_issue 3667910 "Failed to lock SW reset semaphore"
run
trap - EXIT
cleanup
test_done
