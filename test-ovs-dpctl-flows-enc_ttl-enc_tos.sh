#!/bin/bash
#
# Test is trying to check rules added to TC from OVS are
# the same (or close to as supported) to OVS normal datapath rules.
#
# Bug SW #1507801: OVS offloading adds TTL matching even though it was not there when hw-offload is false
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"

local_tun="2.2.2.2"
remote_tun="2.2.2.3"

function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
}

enable_switchdev
unbind_vfs
set_eswitch_inline_mode_transport
bind_vfs
require_interfaces REP
cleanup

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 vxlan0 -- set interface vxlan0 type=vxlan options:local_ip=$local_tun options:remote_ip=$remote_tun options:key=42 options:dst_port=4789
UFID="ufid:c5f9a0b1-3399-4436-b742-30825c64a1e5"

# XXX
# ovs-dpctl doesn't work as it hw-offload value is not read from other_config.
# ovs-appctl dpctl needs ufid because of a check ufid exists. why? we can generate one? function exported?

# XXX
# Adding flow gets deleted right away and in the log we used used>10.. why its not 0?
# In tc filter show used is 0.

function is_ovs_2_10() {
    ovs-vsctl --version | grep -q 2.10
}

dump_sleep=":"
if is_ofed && is_ovs_2_10 ; then
    dump_sleep="sleep 0.2"
fi

function add_flow() {
    m=`ovs-appctl dpctl/add-flow $flow 2 ; $dump_sleep ; ovs_dump_tc_flows | grep -m1 1.1.1.1`
    if [ -n "$m" ]; then
        return 0
    fi

    local tmp="ovs_dump_ovs_flows | grep -m 1.1.1.1"
    if [ -n "$tmp" ]; then
        echo $flow
        err "Rule not in tc"
        return 1
    fi

    m=`ovs-appctl dpctl/add-flow $flow 2 ; $dump_sleep ; ovs_dump_tc_flows | grep -m1 1.1.1.1`
    if [ -z "$m" ]; then
        err "Failed to add test flow: $flow"
        return 1
    fi
    return 0
}

function add_sw_flow() {
    sw=`ovs-dpctl add-flow $flow 2 ; ovs-dpctl dump-flows | grep recirc | grep -m1 1.1.1.1`
    [ -z "$sw" ] && sw=`ovs-dpctl add-flow $flow 2 ; ovs-dpctl dump-flows | grep recirc | grep -m1 1.1.1.1`
    if [ -z "$sw" ]; then
        err "Failed to add sw flow: $flow"
        return 1
    fi
    return 0
}

function compare_keys_with_sw_flow() {
    ovs-dpctl del-flows && sleep 0.5
    add_sw_flow $flow
    keys=`echo $m | grep -o -E "[a-z0-9]+[(=]" | tr -d "=("`
    for k in $keys; do
        if ! echo $sw | grep -q $k ; then
            echo flow $m
            err "Didn't expect $k in flow"
        fi
    done
}

function compare_with_sw_flow() {
    ovs-dpctl del-flows && sleep 0.5
    add_sw_flow $flow
    sw2=`echo $sw | cut -d" " -f1`
    sw2=${sw2:13}
    if [ "$m" != "$sw2" ]; then
        echo flow1 $m
        echo flow2 $sw2
        err "Expected flows to be the same"
    fi
}

function verify_key_in_flow() {
    local key=$1
    ovs-dpctl del-flows && sleep 0.5
    add_sw_flow $flow
    in_m=`echo $m | grep -o "$key([^)]*)"`
    in_sw=`echo $sw | grep -o "$key([^)]*)"`
    if [ "$in_m" != "$in_sw" ]; then
        m=`echo $m | cut -d" " -f1`
        sw=`echo $sw | cut -d" " -f1`
        sw=${sw:13}
        echo flow1 $m
        echo flow2 $sw
        err "Expected $key() to be the same"
    fi
}

function test_enc_ttl_mask_0() {
    title 'Test enc_ttl mask 0'
    flow="$UFID,recirc_id(0),tunnel(tun_id=0x2a,src=2.2.2.3,dst=2.2.2.2,tp_dst=4789,ttl=64/0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow $flow
    # not expecting ttl
    compare_keys_with_sw_flow
}

function test_enc_ttl_mask_1() {
    title 'Test ecn_ttl mask 1'
    flow="$UFID,recirc_id(0),tunnel(tun_id=0x2a,src=2.2.2.3,dst=2.2.2.2,tp_dst=4789,ttl=64/1),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow $flow
    verify_key_in_flow tunnel
}

function test_enc_ttl_mask_ff() {
    title 'Test enc_ttl mask ff'
    flow="$UFID,recirc_id(0),tunnel(tun_id=0x2a,src=2.2.2.3,dst=2.2.2.2,tp_dst=4789,ttl=64/0xff),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow $flow
    verify_key_in_flow tunnel
}

function test_enc_tos_mask_0() {
    title 'Test enc_tos mask 0'
    flow="$UFID,recirc_id(0),tunnel(tun_id=0x2a,src=2.2.2.3,dst=2.2.2.2,tp_dst=4789,tos=0x1/0,ttl=0/0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow $flow
    # not expecting tos
    compare_keys_with_sw_flow
}

function test_enc_tos_mask_1() {
    title 'Test enc_tos mask 1'
    flow="$UFID,recirc_id(0),tunnel(tun_id=0x2a,src=2.2.2.3,dst=2.2.2.2,tp_dst=4789,tos=0x2/1,ttl=0/0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow $flow
    verify_key_in_flow tunnel
}

function test_enc_tos_mask_ff() {
    title 'Test enc_tos mask ff'
    flow="$UFID,recirc_id(0),tunnel(tun_id=0x2a,src=2.2.2.3,dst=2.2.2.2,tp_dst=4789,tos=0xff/0xff,ttl=0/0),in_port(3),eth(src=56:52:2d:21:4d:93,dst=92:c1:04:ce:fd:51),eth_type(0x0800),ipv4(src=1.1.1.1)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow $flow
    verify_key_in_flow tunnel
}



test_enc_ttl_mask_0
test_enc_ttl_mask_1
test_enc_ttl_mask_ff

test_enc_tos_mask_0
test_enc_tos_mask_1
test_enc_tos_mask_ff

cleanup
test_done
