#!/bin/bash
#
# Basic VF LAG test with tc shared block
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding

config_sriov 2
# TODO require vf lag support ?
reset_tc $NIC

local_ip="2.2.2.2"
remote_ip="2.2.2.3"
dst_mac="e4:1d:2d:fd:8b:02"
dst_port=1234
id=98

function tc_filter() {
    eval2 tc filter $@ && success
}

function verify_in_hw() {
    local dev=$1
    local prio=$2
    tc filter show dev $dev ingress prio $prio | grep -q -w in_hw || err "rule not in hw dev $dev"
}

function is_bonded() {
    dmesg | tail -n10 | grep -E "mlx5_core [0-9.:]+ lag map port 1:. port 2:."
    return $?
}

function config_bonding() {
    ip link add name bond0 type bond || fail "Failed to create bond interface"
    ip link set dev bond0 type bond mode active-backup || fail "Failed to set bond mode"
    ip link set dev $1 down
    ip link set dev $2 down
    ip link set dev $1 master bond0
    ip link set dev $2 master bond0
    ip link set dev bond0 up
    if ! is_bonded ; then
        err "Driver bond failed"
    fi
    reset_tc bond0
}

function config_shared_block() {
    for i in bond0 $NIC $NIC2 ; do
        tc qdisc del dev $i ingress
        tc qdisc add dev $i ingress_block 22 ingress
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
    for i in bond0 ens1f0 ens1f1 ; do
        tc qdisc del dev $i ingress_block 22 ingress &>/dev/null
    done
}

function cleanup() {
    clean_shared_block
    ip link set dev $NIC nomaster
    ip link set dev $NIC2 nomaster
    ip link del bond0 &>/dev/null
    ifconfig $NIC down
}

function config_vxlan() {
    ip link add vxlan1 type vxlan id $id dev $NIC dstport $dst_port
    ip link set vxlan1 up
    ip addr add ${local_ip}/24 dev $NIC
    tc qdisc add dev vxlan1 ingress
    ip link set $NIC up
    ip n add $remote_ip lladdr $dst_mac dev $NIC
}

function clean_vxlan() {
    ip link del dev vxlan1 2> /dev/null
    ip n del ${remote_ip} dev $NIC 2>/dev/null
    ip n del ${remote_ip6} dev $NIC 2>/dev/null
    ip addr flush dev $NIC
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
    tc_filter add dev $REP protocol arp parent ffff: prio 8 \
        flower dst_mac $dst_mac skip_sw \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1

    # decap
    title "- decap"
    tc_filter add dev vxlan1 protocol arp parent ffff: prio 9 \
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
    tc_filter add block 22 protocol arp parent ffff: prio 5 \
        flower dst_mac $dst_mac action drop
    verify_in_hw $NIC 5
    verify_in_hw $NIC2 5
}

function test_add_redirect_rule() {
    title "- bond0 -> $REP"
    tc_filter add block 22 protocol arp parent ffff: prio 3 \
        flower dst_mac $dst_mac \
        action mirred egress redirect dev $REP
    verify_in_hw $NIC 3
    verify_in_hw $NIC2 3

    title "- $REP -> bond0"
    tc_filter add dev $REP protocol arp parent ffff: prio 3 \
        flower dst_mac $dst_mac skip_sw \
        action mirred egress redirect dev bond0
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
