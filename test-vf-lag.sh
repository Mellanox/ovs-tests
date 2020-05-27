#!/bin/bash
#
# Basic VF LAG test with tc shared block
#
# Bug SW #1778222: [upstream][VF lag] tx traffic from vf to the pf which the vf is not created on is not offloaded
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding

# When rules added with metadata instead of source_port,
# we cannot verify it because of mlxdump limitation not showing reg_c content.
# so set to true checking kernels not using metadata or false if using metadata
# to avoid false error.
VERIFY_SOURCE_PORT=false

config_sriov 2
# TODO require vf lag support ?
reset_tc $NIC

local_ip="2.2.2.2"
remote_ip="2.2.2.3"
dst_mac="e4:1d:2d:fd:8b:02"
dst_port=1234
id=98

function err_or_warn() {
    if $VERIFY_SOURCE_PORT ; then
        err $@
    else
        warn $@
    fi
}

function verify_hw_rules() {
    local src=$1
    local dst=$2
    local i
    local mac=`echo $dst_mac | tr -d :`
    mac=${mac::6}

    local src_tag="source_port"
    local dst_tag="destination_id"

    for i in 0 1 ; do
        title "- verify hw rule on port$i"
        mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
        grep -A5 $mac /tmp/port$i | grep -q "$src_tag\s*:$src" || err_or_warn "Expected rule with source port $src"
        grep -A5 $mac /tmp/port$i | grep -q "$dst_tag\s*:$dst" || err "Expected rule with dest port $dst"
    done
}

function config_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress
        tc qdisc add dev $i ingress_block 22 ingress || err "Failed to add ingress_block"
    done
}

function config() {
    echo "- Config"
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    reset_tc $NIC $NIC2 $REP
    config_bonding $NIC $NIC2
    config_shared_block
}

function clean_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress_block 22 ingress &>/dev/null
    done
}

function cleanup() {
    clean_shared_block
    clear_bonding
    ifconfig $NIC down
}

function config_vxlan() {
    local nic1="bond0"
    ip link add vxlan1 type vxlan id $id dev $nic1 dstport $dst_port
    ip link set vxlan1 up
    ip addr add ${local_ip}/24 dev $nic1
    tc qdisc add dev vxlan1 ingress
    ip link set $nic1 up
    ip n add $remote_ip lladdr $dst_mac dev $nic1
}

function clean_vxlan() {
    local nic1="bond0"
    ip link del dev vxlan1 2> /dev/null
    ip n del ${remote_ip} dev $nic1 2>/dev/null
    ip addr flush dev $nic1
}

function add_vxlan_rule() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    # tunnel key set
    ifconfig $NIC up
    reset_tc $REP $NIC vxlan1

    # encap
    title "- encap"
    tc_filter_success add dev $REP protocol arp parent ffff: prio 8 \
        flower dst_mac $dst_mac skip_sw \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1

    # decap
    title "- decap"
    tc_filter_success add dev vxlan1 protocol arp parent ffff: prio 9 \
        flower dst_mac $dst_mac \
            enc_src_ip $remote_ip \
            enc_dst_ip $local_ip \
            enc_dst_port $dst_port \
            enc_key_id $id \
        action tunnel_key unset \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev $REP
    verify_in_hw vxlan1 9

    reset_tc $REP $NIC vxlan1
}

function test_add_vxlan_rule() {
    config_vxlan
    add_vxlan_rule $local_ip $remote_ip
    clean_vxlan
}

function test_add_drop_rule() {
    tc_filter_success add block 22 protocol arp parent ffff: prio 5 \
        flower dst_mac $dst_mac action drop
    verify_in_hw $NIC 5
    verify_in_hw $NIC2 5
}

function test_add_redirect_rule() {
    title "- bond0 -> $REP"
    tc_filter_success add block 22 protocol arp parent ffff: prio 3 \
        flower dst_mac $dst_mac \
        action mirred egress redirect dev $REP
    verify_in_hw $NIC 3
    verify_in_hw $NIC2 3
    verify_hw_rules 0xffff 0x1

    title "- $REP -> bond0"
    tc_filter_success add dev $REP protocol arp parent ffff: prio 3 \
        flower dst_mac $dst_mac skip_sw \
        action mirred egress redirect dev bond0
    verify_hw_rules 0x1 0xffff
}

function do_cmd() {
    title $1
    eval $1
}


trap cleanup EXIT
cleanup
config
fail_if_err
do_cmd test_add_drop_rule
do_cmd test_add_redirect_rule
do_cmd test_add_vxlan_rule
cleanup
test_done
