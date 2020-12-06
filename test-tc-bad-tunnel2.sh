#!/bin/bash
#
# Catch a bug using encap pointing to bad tun_info
#
# note: this is an example test that doesn't verify the dump at the end
# user needs to verify manually.
#
# IGNORE_FROM_TEST_ALL
#
# case2
# create rule1 encap1 - e1
# create rule2 encap1 - e1
# del rule1 encap1 (e1->tun_info freed)
# add rule3 encap2 (in parse action e1->tun_info will be overridden.
#                   lookup will find e1->tun_info ok but attaching
#                   using e1 will result in wrong hw encap.)
#
# add 30 rules m1 encaps
# add 30 rules m2 same encaps
# del 30 rules m1 to release all tun_info
# add 30 rules m3 new encaps
# if a rule m3 use e from m2 rule then its the bug.
# m3 encaps should be after last m2 encap and increamental.
# can also dump m3 encaps and check none being used also by m2.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"

config_sriov 2
enable_switchdev
require_interfaces REP
unbind_vfs
bind_vfs
reset_tc $REP

vx=vxlan1
vxlan_port=4789

function cleanup() {
    ip link set $NIC down
    ip link del $vx &>/dev/null
    ip -all netns delete
    reset_tc $REP
}
trap cleanup EXIT

function create_vxlan() {
    title "create vxlan interface"
    ip link del $vx &>/dev/null
    ip link add $vx type vxlan dstport $vxlan_port external
    [ $? -ne 0 ] && fail "Failed to create vxlan interface"
    ip link set dev $vx up
    ip a show dev $vx
}

function add_vxlan_rule() {
    local mac=$1
    local dst=$2
    local prio=$3

    TUNNEL_KEY_SET1="action tunnel_key set
        src_ip $ip_src
        dst_ip $dst
        dst_port 4789
        id 102
        ttl 64
        nocsum"

    tc_filter add dev $REP ingress protocol ip prio $prio flower skip_sw \
        dst_mac $mac \
        $TUNNEL_KEY_SET1 pipe \
        action mirred egress redirect dev $vx
}

function test_tunnel() {
    local ip_src=20.12.11.1

    title "Test tunnel"
    config_vf ns0 $VF $REP $IP1
    create_vxlan
    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ip link set $NIC up

    encaps=100

    title "add tc rules m1 & m2"
    for i in `seq $encaps`; do
        ip neigh replace 20.12.12.$i lladdr e4:11:22:11:55:11 dev $NIC
        add_vxlan_rule e4:11:22:11:77:67 20.12.12.$i 1
        add_vxlan_rule e4:11:22:11:77:68 20.12.12.$i 2
    done

    title "del tc rules m1"
    tc_filter del dev $REP ingress prio 1

    title "add tc rules m3"
    for i in `seq $encaps`; do
        ip neigh replace 20.12.13.$i lladdr e4:11:22:11:55:12 dev $NIC
        add_vxlan_rule e4:11:22:11:77:69 20.12.13.$i 3
    done

    fail_if_err

    title "fw dump"
    fw_dump dump1
    warn "Not verifiying the dump"

    reset_tc $REP
    ip link set $NIC down
}


cleanup
test_tunnel
test_done
