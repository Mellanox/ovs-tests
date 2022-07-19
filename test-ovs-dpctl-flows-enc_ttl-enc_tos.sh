#!/bin/bash
#
# Test is trying to check rules added to TC from OVS are
# the same (or close to as supported) to OVS normal datapath rules.
#
# Bug SW #1507801: OVS offloading adds TTL matching even though it was not there when hw-offload is false
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
require_interfaces REP
start_clean_openvswitch

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 vxlan0 -- set interface vxlan0 type=vxlan options:local_ip=$local_tun options:remote_ip=$remote_tun options:key=42 options:dst_port=4789

function test_enc_ttl_mask_0() {
    title 'Test enc_ttl mask 0'
    flow="$UFID,recirc_id(0),tunnel(tun_id=0x2a,src=2.2.2.3,dst=2.2.2.2,tp_dst=4789,ttl=64/0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow
    # not expecting ttl
    compare_keys_with_sw_flow
}

function test_enc_ttl_mask_1() {
    title 'Test ecn_ttl mask 1'
    flow="$UFID,recirc_id(0),tunnel(tun_id=0x2a,src=2.2.2.3,dst=2.2.2.2,tp_dst=4789,ttl=64/1),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow
    verify_key_in_flow tunnel
}

function test_enc_ttl_mask_ff() {
    title 'Test enc_ttl mask ff'
    flow="$UFID,recirc_id(0),tunnel(tun_id=0x2a,src=2.2.2.3,dst=2.2.2.2,tp_dst=4789,ttl=64/0xff),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow
    verify_key_in_flow tunnel
}

function test_enc_tos_mask_0() {
    title 'Test enc_tos mask 0'
    flow="$UFID,recirc_id(0),tunnel(tun_id=0x2a,src=2.2.2.3,dst=2.2.2.2,tp_dst=4789,tos=0x1/0,ttl=0/0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow
    # not expecting tos
    compare_keys_with_sw_flow
}

function test_enc_tos_mask_1() {
    title 'Test enc_tos mask 1'
    flow="$UFID,recirc_id(0),tunnel(tun_id=0x2a,src=2.2.2.3,dst=2.2.2.2,tp_dst=4789,tos=0x2/1,ttl=0/0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow
    verify_key_in_flow tunnel
}

function test_enc_tos_mask_ff() {
    title 'Test enc_tos mask ff'
    flow="$UFID,recirc_id(0),tunnel(tun_id=0x2a,src=2.2.2.3,dst=2.2.2.2,tp_dst=4789,tos=0xff/0xff,ttl=0/0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow
    verify_key_in_flow tunnel
}



test_enc_ttl_mask_0
test_enc_ttl_mask_1
test_enc_ttl_mask_ff

test_enc_tos_mask_0
test_enc_tos_mask_1
test_enc_tos_mask_ff

ovs_clear_bridges
test_done
