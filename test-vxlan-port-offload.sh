#!/bin/bash
#
# Test insert vxlan rule after driver reload
# - create vxlan interface
# - reload driver
# - add vxlan rule
#
# Bug SW #1335481: vxlan not offloaded after reloading mlx5_core
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function tc_filter() {
    eval2 tc filter $@ && success || err
}

function clean_ingress() {
    for i in `ls -1 /sys/class/net/` ; do tc qdisc del dev $i ingress 2>/dev/null ; done
}

function __test_vxlan() {
    local ip_src=$1
    local ip_dst=$2
    local skip

    title " - create vxlan interface"
    # note: we support adding decap to vxlan interface only.
    vx=vxlan1
    vxlan_port=4789
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dstport $vxlan_port external
    ip link set dev $vx up
    tc qdisc add dev $vx ingress

    ip a show dev $vx

    title " - reload modules"
    clean_ingress
    reload_modules
    enable_switchdev
    bind_vfs
    ifconfig $NIC up
    ifconfig $REP up
    reset_tc_nic $NIC
    reset_tc_nic $REP

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ip neigh add $ip_dst lladdr e4:11:22:11:55:55 dev $NIC

    title " - add vxlan rule"
    skip='skip_sw'
        title "- skip:$skip"
        reset_tc $REP
        reset_tc $vx
        title "    - encap"
        tc_filter add dev $REP protocol 0x806 parent ffff: \
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
        title "    - decap"
        tc_filter add dev $vx protocol 0x806 parent ffff: \
                    flower \
                            $skip \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            enc_src_ip $ip_src \
                            enc_dst_ip $ip_dst \
                            enc_dst_port $vxlan_port \
                            enc_key_id 100 \
                    action tunnel_key unset \
                    action mirred egress redirect dev $REP

    reset_tc $NIC
    reset_tc $REP
    reset_tc $vx
    ip addr flush dev $NIC
    ip link del $vx
}

function test_basic_vxlan_ipv4() {
    __test_vxlan \
                        20.1.11.1 \
                        20.1.12.1
}

title "Test adding vxlan rule after creating vxlan interfaces and reloading modules"
test_basic_vxlan_ipv4
check_for_err "isn't an offloaded vxlan udp dport"

test_done
