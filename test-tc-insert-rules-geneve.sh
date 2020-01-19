#!/bin/bash
#
# Test insert geneve rule with TLV options
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function tc_filter() {
    eval2 tc filter $@ && success
}

function __test_geneve() {
    local ip_src=$1
    local ip_dst=$2
    local skip

    title " - create geneve interface"
    gv=geneve1
    geneve_port=6081
    ip link del $gv >/dev/null 2>&1
    ip link add dev $gv type geneve dstport $geneve_port external
    [ $? -ne 0 ] && err "Failed to create geneve interface" && return 1
    ip link set dev $gv up
    tc qdisc add dev $gv ingress

    ip a show dev $gv

    enable_switchdev
    ifconfig $NIC up
    ifconfig $REP up
    reset_tc $NIC
    reset_tc $REP

    m=`ip addr show $gv 2>&1`
    [ $? -ne 0 ] && fail $m

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ip neigh add $ip_dst lladdr e4:11:22:11:55:55 dev $NIC

    reset_tc $REP
    reset_tc $gv
    title "    - encap"
    tc_filter add dev $REP protocol 0x806 parent ffff: prio 1 chain 1 \
                    flower \
                            skip_sw \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                    action tunnel_key set \
                    src_ip $ip_src \
                    dst_ip $ip_dst \
                    dst_port $geneve_port \
                    id 100 \
                    geneve_opts 1234:56:0708090a \
                    action mirred egress redirect dev $gv

    title "    - decap"
    tc_filter add dev $gv protocol 0x806 parent ffff: prio 2 chain 1 \
                    flower \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            enc_src_ip $ip_src \
                            enc_dst_ip $ip_dst \
                            enc_dst_port $geneve_port \
                            enc_key_id 100 \
                            geneve_opts 0102:34:05060708 \
                    action tunnel_key unset \
                    action mirred egress redirect dev $REP
    verify_in_hw $gv 2

    reset_tc $NIC
    reset_tc $REP
    reset_tc $gv
    ip addr flush dev $NIC
    ip link del $gv
}

function test_geneve_ipv4() {
    __test_geneve \
                        20.1.11.1 \
                        20.1.12.1
}

title "Test adding geneve rules"
test_geneve_ipv4

test_done
