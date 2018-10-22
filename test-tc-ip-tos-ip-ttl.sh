#!/bin/bash
#
# Bug SW #1507156: [upstream] Failed to set tos and ttl matching on ConnectX-4 Lx
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


not_relevant_for_cx4


function test_ip_tos_and_ip_ttl() {
    local nic=$1

    start_check_syndrome
    reset_tc_nic $nic
    tc_filter add dev $nic protocol ip ingress prio 1 flower skip_sw dst_mac 7c:fe:90:7b:76:5c ip_proto icmp ip_tos 0x30 ip_ttl 63 action drop
    check_syndrome
}

function __test_basic_vxlan() {
    local ip_src=$1
    local ip_dst=$2
    # note: we support adding decap to vxlan interface only.
    vx=vxlan1
    vxlan_port=4789
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dev $NIC dstport $vxlan_port external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set dev $vx up
    tc qdisc add dev $vx ingress

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ifconfig $NIC up
    ip neigh add $ip_dst lladdr e4:11:22:11:55:55 dev $NIC

    reset_tc_nic $NIC
    reset_tc_nic $REP

    reset_tc $REP
    reset_tc $vx

    start_check_syndrome

    tc_filter add dev $vx protocol 0x806 parent ffff: prio 1 \
                flower \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                        enc_src_ip $ip_src \
                        enc_dst_ip $ip_dst \
                        enc_dst_port $vxlan_port \
                        enc_key_id 100 \
                        enc_tos 0x30 \
                        enc_ttl 63 \
                action tunnel_key unset \
                action mirred egress redirect dev $REP || return $?
    # because of upstream issue adding decap rule in skip_sw we add with
    # policy none and verify in_hw bit.
    # Bug SW #1360599: [upstream] decap rule offload attempt with skip_sw fails
    tc filter show dev $vx ingress prio 1 | grep -q -w in_hw || err "Decap rule not in hw"

    check_syndrome

    reset_tc $NIC
    reset_tc $REP
    reset_tc $vx
    ip addr flush dev $NIC
    ip link del $vx
    tmp=`dmesg | tail -n20 | grep "encap size" | grep "too big"`
    if [ "$tmp" != "" ]; then
        err "$tmp"
    fi
}

function test_basic_vxlan_ipv4() {
    __test_basic_vxlan \
                        20.1.11.1 \
                        20.1.12.1
}


enable_switchdev

title "Test rule with ip_tos and ip_ttl on $NIC"
test_ip_tos_and_ip_ttl $NIC

title "Test rule with ip_tos and ip_ttl on $REP"
test_ip_tos_and_ip_ttl $REP

title "Test vxlan decap rule with enc_tos and enc_ttl"
test_basic_vxlan_ipv4

test_done
