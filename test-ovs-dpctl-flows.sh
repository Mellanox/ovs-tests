#!/bin/bash
#
# Test adding offload flows using ovs dpctl and verify rules against ovs sw rule
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

enable_switchdev_if_no_rep $REP $REP2
unbind_vfs
set_eswitch_inline_mode_transport
bind_vfs
require_interfaces REP REP2
cleanup

echo "setup ovs"
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 $REP2
UFID="ufid:c5f9a0b1-3399-4436-b742-30825c64a1e5"

ipv4=1.1.1.1
ipv6=2002:db8:0:f101::55

function add_flow() {
    local g=$1
    m=`ovs-appctl dpctl/add-flow $flow 2 ; ovs_dpctl_dump_flows | grep -m1 $g*`
    [ -z "$m" ] && m=`ovs-appctl dpctl/add-flow $flow 2 ; ovs_dpctl_dump_flows | grep -m1 $g*`
    if [ -z "$m" ]; then
        err "Failed to add test flow: $flow"
        return 1
    fi
    return 0
}

function add_sw_flow() {
    local ip=$1
    sw=`ovs-dpctl add-flow $flow 2 ; ovs-dpctl dump-flows | grep recirc | grep -m1 $ip*`
    [ -z "$sw" ] && sw=`ovs-dpctl add-flow $flow 2 ; ovs-dpctl dump-flows | grep recirc | grep -m1 $ip*`
    if [ -z "$sw" ]; then
        err "Failed to add sw flow: $flow"
        return 1
    fi
    return 0
}

function verify_keys_in_flow() {
    local ip=$1
    local keys="${@:2}"
    local key
    ovs-dpctl del-flows && sleep 0.5
    add_sw_flow $ip
    for key in $keys; do
        in_m=`echo $m | grep -o "$key([^)]*)"`
        in_sw=`echo $sw | grep -o "$key([^)]*)"`
        if [ "$in_m" != "$in_sw" ]; then
            m2=`echo $m | cut -d" " -f1`
            sw2=`echo $sw | cut -d" " -f1`
            sw=${sw:13}
            echo flow1 $m2
            echo flow2 $sw2
            err "Expected $key() to be the same"
        fi
    done
}

function test_appctl_rule_tcp() {
    title 'Test appctl rule TCP'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:4d:93/FF:FF:FF:FF:FF:FF,dst=92:c1:04:ce:fd:51/FF:FF:FF:FF:FF:FF),eth_type(0x0800),ipv4(src=$ipv4/255.255.255.0,dst=2.2.2.2/255.255.255.0,proto=0x6),tcp(src=8080/0xff00,dst=8080/0xff),tcp_flags(0xff/0xff)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow $ipv4 || return 1
    verify_keys_in_flow $ipv4 eth eth_type ipv4 tcp tcp_flags
}

function test_appctl_rule_udp() {
    title 'Test appctl rule UDP'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:4d:93/FF:FF:FF:FF:FF:FF,dst=92:c1:04:ce:fd:51/FF:FF:FF:FF:FF:FF),eth_type(0x0800),ipv4(src=$ipv4/255.255.255.0,dst=2.2.2.2/255.255.255.0,proto=0x11),udp(src=80/0xff00,dst=443/0xff)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow $ipv4 || return 1
    verify_keys_in_flow $ipv4 eth eth_type ipv4 udp
}

function test_appctl_rule_tcp_ipv6() {
    title 'Test appctl rule TCP ipv6'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:4d:93/FF:FF:FF:FF:FF:FF,dst=92:c1:04:ce:fd:51/FF:FF:FF:FF:FF:FF),eth_type(0x86DD),ipv6(src=$ipv6,dst=2002:db8:0:f101::1,proto=0x6),tcp(src=8080/0xff00,dst=8080/0xff),tcp_flags(0xff/0xff)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow $ipv6 || return 1
    verify_keys_in_flow $ipv6 eth eth_type ipv6 tcp tcp_flags
}

function test_appctl_rule_udp_ipv6() {
    title 'Test appctl rule UDP ipv6'
    flow="$UFID,recirc_id(0),in_port(3),eth(src=56:52:2d:21:4d:93/FF:FF:FF:FF:FF:FF,dst=92:c1:04:ce:fd:51/FF:FF:FF:FF:FF:FF),eth_type(0x86DD),ipv6(src=$ipv6,dst=2002:db8:0:f101::1,proto=0x11),udp(src=80/0xff00,dst=443/0xff)"
    ovs-dpctl del-flows && sleep 0.5
    add_flow $ipv4 || return 1
    verify_keys_in_flow $ipv6 eth eth_type ipv6 udp
}

start_check_syndrome

test_appctl_rule_tcp
test_appctl_rule_udp
test_appctl_rule_tcp_ipv6
test_appctl_rule_udp_ipv6

check_syndrome
cleanup
test_done