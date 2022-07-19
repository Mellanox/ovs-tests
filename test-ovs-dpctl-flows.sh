#!/bin/bash
#
# Test adding offload flows using ovs dpctl and verify rules against ovs sw rule
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-ovs-dpctl.sh

VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"

local_tun="2.2.2.2"
remote_tun="2.2.2.3"

enable_switchdev
unbind_vfs
set_eswitch_inline_mode_transport
bind_vfs
require_interfaces REP REP2
start_clean_openvswitch

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 $REP2

ipv4="1.1.1.1"
ipv6="2002:db8:0:f101::55"

function test_appctl_rule_tcp() {
    title 'Test appctl rule TCP'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:66:66/FF:FF:FF:FF:FF:FF,dst=92:c1:04:ce:fd:51/FF:FF:FF:FF:FF:FF),eth_type(0x0800),ipv4(src=$ipv4/255.255.255.0,dst=2.2.2.2/255.255.255.0,proto=0x6),tcp(src=8080/0xff00,dst=8080/0xff),tcp_flags(0xff/0xff)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow 66:66 || return 1
    verify_keys_in_flow 66:66 eth eth_type ipv4 tcp tcp_flags
}

function test_appctl_rule_udp() {
    title 'Test appctl rule UDP'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:17:17/FF:FF:FF:FF:FF:FF,dst=92:c1:04:ce:fd:51/FF:FF:FF:FF:FF:FF),eth_type(0x0800),ipv4(src=$ipv4/255.255.255.0,dst=2.2.2.2/255.255.255.0,proto=0x11),udp(src=80/0xff00,dst=443/0xff)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow 17:17 || return 1
    verify_keys_in_flow 17:17 eth eth_type ipv4 udp
}

function test_appctl_rule_tcp_ipv6() {
    title 'Test appctl rule TCP ipv6'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:18:18/FF:FF:FF:FF:FF:FF,dst=92:c1:04:ce:fd:51/FF:FF:FF:FF:FF:FF),eth_type(0x86DD),ipv6(src=$ipv6,dst=2002:db8:0:f101::1,proto=0x6),tcp(src=8080/0xff00,dst=8080/0xff),tcp_flags(0xff/0xff)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow 18:18 || return 1
    verify_keys_in_flow 18:18 eth eth_type ipv6 tcp tcp_flags
}

function test_appctl_rule_udp_ipv6() {
    title 'Test appctl rule UDP ipv6'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:19:19/FF:FF:FF:FF:FF:FF,dst=92:c1:04:ce:fd:51/FF:FF:FF:FF:FF:FF),eth_type(0x86DD),ipv6(src=$ipv6,dst=2002:db8:0:f101::1,proto=0x11),udp(src=80/0xff00,dst=443/0xff)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow 19:19 || return 1
    verify_keys_in_flow 19:19 eth eth_type ipv6 udp
}


test_appctl_rule_tcp
test_appctl_rule_udp
test_appctl_rule_tcp_ipv6
test_appctl_rule_udp_ipv6

ovs_clear_bridges
test_done
