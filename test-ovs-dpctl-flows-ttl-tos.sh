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

enable_switchdev
unbind_vfs
set_eswitch_inline_mode_transport
bind_vfs
require_interfaces REP
start_clean_openvswitch

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 $NIC
ifconfig $VF 1.1.1.1/24 up

function test_ttl_mask_0() {
    title 'Test ttl mask 0'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1,ttl=64/0)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow || return 1
    # not expecting ttl
    compare_keys_with_sw_flow
}

function test_ttl_mask_1() {
    title 'Test ttl mask 1'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1,ttl=64/1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow || return 1
    verify_key_in_flow ipv4
}

function test_ttl_mask_ff() {
    title 'Test ttl mask ff'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1,ttl=64/0xff)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow || return 1
    verify_key_in_flow ipv4
}

function test_tos_mask_0() {
    title 'Test tos mask 0'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1,tos=0x1/0,ttl=0/0)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow || return 1
    # not expecting tos
    compare_keys_with_sw_flow
}

function test_tos_mask_1() {
    title 'Test tos mask 1'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1,tos=0x2/1,ttl=0/0)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow || return 1
    verify_key_in_flow ipv4
}

function test_tos_mask_ff() {
    title 'Test tos mask ff'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1,tos=0xff/0xff,ttl=0/0)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow || return 1
    verify_key_in_flow ipv4
}



test_ttl_mask_0
test_ttl_mask_1
test_ttl_mask_ff

test_tos_mask_0
test_tos_mask_1
test_tos_mask_ff

ifconfig $VF 0
ovs_clear_bridges
test_done
