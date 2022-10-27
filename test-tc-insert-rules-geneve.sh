#!/bin/bash
#
# Test insert geneve rule with TLV options
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov
enable_switchdev

function config_geneve() {
    title "- create geneve interface"
    gv=geneve1
    geneve_port=6081
    ip link del $gv >/dev/null 2>&1
    ip link add dev $gv type geneve dstport $geneve_port external
    [ $? -ne 0 ] && err "Failed to create geneve interface" && return 1
    ip link set dev $gv up
    tc qdisc add dev $gv ingress
    ip a show dev $gv
}

function __test_geneve() {
    local ip_src=$1
    local ip_dst=$2
    local skip

    tc_test_verbose

    config_geneve

    ifconfig $NIC up
    ifconfig $REP up

    m=`ip addr show $gv 2>&1`
    [ $? -ne 0 ] && fail $m

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ip neigh add $ip_dst lladdr e4:11:22:11:55:55 dev $NIC

    reset_tc $REP $NIC $gv

    title "- encap"
    tc_filter_success add dev $REP protocol 0x806 parent ffff: prio 1 chain 0 \
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
    reset_tc $REP

    title "- decap"
    tc_filter_success add dev $gv protocol 0x806 parent ffff: prio 2 chain 0 \
                    flower $tc_verbose \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            enc_src_ip $ip_dst \
                            enc_dst_ip $ip_src \
                            enc_dst_port $geneve_port \
                            enc_key_id 100 \
                            geneve_opts 0102:34:05060708 \
                    action tunnel_key unset \
                    action mirred egress redirect dev $REP
    verify_in_hw $gv 2
    reset_tc $gv

    title "- decap geneve_opts with goto"
    tc_filter_success add dev $gv protocol 0x806 parent ffff: prio 12 chain 0 \
                    flower $tc_verbose \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            enc_src_ip $ip_dst \
                            enc_dst_ip $ip_src \
                            enc_dst_port $geneve_port \
                            enc_key_id 100 \
                            geneve_opts 0102:34:05060708 \
                    action goto chain 1
    verify_in_hw $gv 12
    reset_tc $gv

    title "- decap geneve_opts mask 0 chain 1 is supported"
    tc_filter_success add dev $gv protocol 0x806 parent ffff: prio 3 chain 1 \
                    flower $tc_verbose \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            enc_src_ip $ip_dst \
                            enc_dst_ip $ip_src \
                            enc_dst_port $geneve_port \
                            enc_key_id 100 \
                            geneve_opts 0102:34:05060708/0:0:00000000 \
                    action tunnel_key unset \
                    action mirred egress redirect dev $REP
    verify_in_hw $gv 3
    reset_tc $gv

    title "- decap geneve_opts multiple chain 0 is not supported"
    tc_filter_success add dev $gv protocol 0x806 parent ffff: prio 4 chain 0 \
                    flower \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            enc_src_ip $ip_dst \
                            enc_dst_ip $ip_src \
                            enc_dst_port $geneve_port \
                            enc_key_id 100 \
                            geneve_opts 0102:34:05060707,0102:34:05060708,0102:34:05060709 \
                    action tunnel_key unset \
                    action mirred egress redirect dev $REP
    # we expect it not_in_hw as we only support 1 option
    verify_not_in_hw $gv 4
    reset_tc $gv

    title "- decap geneve_opts chain 1 partial data mask"
    tc_filter_success add dev $gv protocol 0x806 parent ffff: prio 3 chain 1 \
                    flower $tc_verbose \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            enc_src_ip $ip_dst \
                            enc_dst_ip $ip_src \
                            enc_dst_port $geneve_port \
                            enc_key_id 100 \
                            geneve_opts 0102:80:00010004/ffff:ff:7fffffff \
                    action tunnel_key unset \
                    action mirred egress redirect dev $REP
    verify_in_hw $gv 3
    reset_tc $gv

    ip addr flush dev $NIC
    ip link del $gv
}

function test_geneve_ipv4() {
    __test_geneve 20.1.11.1 20.1.12.1
}

add_expected_error_msg "Failed to parse tunnel attributes"

title "Test adding geneve rules"
test_geneve_ipv4

test_done
