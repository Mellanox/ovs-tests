#!/bin/bash
#
# Test insert vxlan rule on chain != 0
#
# Bug SW #2466306: [Upstream][CT] Traffic is not offloaded over vxlan ipv6 tunneling

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
enable_switchdev
require_interfaces REP
unbind_vfs
bind_vfs

function __test_basic_vxlan() {
    local ip_src=$1
    local ip_dst=$2
    local vxlan_port=$3
    local skip
    # note: we support adding decap to vxlan interface only.
    vx=vxlan1
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dev $NIC dstport $vxlan_port external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set dev $vx up
    tc qdisc add dev $vx ingress

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ifconfig $NIC up
    ip neigh replace $ip_dst lladdr e4:11:22:11:55:55 dev $NIC

    reset_tc $NIC $REP $vx

    skip=""
    skip_sw_wa=0
    chain=1

    title "- encap"
    tc_filter_success add dev $REP protocol 0x800 parent ffff: prio 1 chain $chain \
                flower \
                        $skip \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                action tunnel_key set \
                src_ip $ip_src \
                dst_ip $ip_dst \
                dst_port $vxlan_port \
                id 100 \
                action mirred egress redirect dev $vx
    title "- decap"
    tc_filter_success add dev $vx protocol 0x800 parent ffff: prio 2 chain $chain \
                flower \
                        $skip \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                        enc_src_ip $ip_dst \
                        enc_dst_ip $ip_src \
                        enc_dst_port $vxlan_port \
                        enc_key_id 100 \
                action tunnel_key unset \
                action mirred egress redirect dev $REP
    tc_filter_success show dev $vx ingress prio 2 | grep -q -w in_hw || err "Decap rule not in hw"

    reset_tc $NIC
    reset_tc $REP
    reset_tc $vx
    ip neigh del $ip_dst lladdr e4:11:22:11:55:55 dev $NIC
    ip addr flush dev $NIC
    ip link del $vx
}

function test_basic_vxlan_ipv6() {
    title "Test vxlan ipv6 on chain 1"
    vxlan_port=4789
    __test_basic_vxlan \
                            2001:0db8:85a3::8a2e:0370:7334 \
                            2001:0db8:85a3::8a2e:0370:7335 \
                            $vxlan_port
}

test_basic_vxlan_ipv6
test_done
