#!/bin/bash
#
# Catch a bug using encap pointing to bad tun_info
#
# note: this is an example test that doesn't verify the dump at the end
# user needs to verify manually.
#
# IGNORE_FROM_TEST_ALL
#
# add vxlan rule1 tun dst ip A  (create e1)
# add vxlan rule2 tun dst ip A  (use e1 tun_info==A)
# del vxlan rule1 (BUG free e->*tun_info) -> e1 tun_info=aaaaaaa
# loop
#     add vxlan rule3 tun dst ip B (either create e2 or use e1-BUG)
#     add vxlan rule4 tun dst ip A (either use e1 or create e3-BUG)
#     del rule3
#     del rule4

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

function test_tunnel() {
    local ip_src=20.12.11.1
    local ip_dst1=20.12.12.1
    local ip_dst2=20.12.13.1

    title "Test tunnel"
    config_vf ns0 $VF $REP $IP1
    create_vxlan
    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ip link set $NIC up
    ip neigh replace $ip_dst1 lladdr e4:11:22:11:55:11 dev $NIC
    ip neigh replace $ip_dst2 lladdr e4:11:22:11:55:22 dev $NIC

    TUNNEL_KEY_SET1="action tunnel_key set
        src_ip $ip_src
        dst_ip $ip_dst1
        dst_port 4789
        id 102
        ttl 64
        nocsum"

    TUNNEL_KEY_SET2="action tunnel_key set
        src_ip $ip_src
        dst_ip $ip_dst2
        dst_port 4789
        id 102
        ttl 64
        nocsum"

    title "add tc rule1 with tunnel1"
    tc_filter add dev $REP ingress protocol ip prio 1 flower skip_sw \
        dst_mac e4:11:22:11:77:66 \
        $TUNNEL_KEY_SET1 pipe \
        action mirred egress redirect dev $vx

    title "add tc rule2 with tunnel1"
    tc_filter add dev $REP ingress protocol ip prio 2 flower skip_sw \
        dst_mac e4:11:22:11:77:67  \
        $TUNNEL_KEY_SET1 pipe \
        action mirred egress redirect dev $vx

    title "del tc rule1"
    tc_filter del dev $REP ingress prio 1

    title "add tc rule3 with tunnel2"
    tc_filter add dev $REP ingress protocol ip prio 3 flower skip_sw \
        dst_mac e4:11:22:11:77:68 \
        $TUNNEL_KEY_SET2 pipe \
        action mirred egress redirect dev $vx

    title "add tc rule4 with tunnel1"
    tc_filter add dev $REP ingress protocol ip prio 4 flower skip_sw \
        dst_mac e4:11:22:11:77:69 \
        $TUNNEL_KEY_SET1 pipe \
        action mirred egress redirect dev $vx

    fail_if_err

    fw_dump dump1

# Example for the bug. last rule created encap 0x4 instead of using encap 0x0
# domain 0x7cdc02, table 0xffff930cb6498300, matcher 0xffff930e60622000, rule 0xffff930f4f686a20
#   match: metadata_reg_c_0: 0x00010000 dmac: e4:11:22:11:77:67, ethertype: 0x0800 
#   action: CTR, index 0x801001 & ENCAP_L2, devx obj id 0x0 & VPORT, num 0xffff
#domain 0x7cdc02, table 0xffff930cb6498300, matcher 0xffff930e60622000, rule 0xffff930f4f686e40
#   match: metadata_reg_c_0: 0x00010000 dmac: e4:11:22:11:77:68, ethertype: 0x0800 
#   action: CTR, index 0x801002 & ENCAP_L2, devx obj id 0x2 & VPORT, num 0xffff
#domain 0x7cdc02, table 0xffff930cb6498300, matcher 0xffff930e60622000, rule 0xffff930f2d7868a0
#   match: metadata_reg_c_0: 0x00010000 dmac: e4:11:22:11:77:69, ethertype: 0x0800 
#   action: CTR, index 0x801000 & ENCAP_L2, devx obj id 0x4 & VPORT, num 0xffff

    reset_tc $REP
    ip link set $NIC down
}


cleanup
test_tunnel
test_done
