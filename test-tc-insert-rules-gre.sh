#!/bin/bash
#
# Test basic gre encap/decap rules
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4

tun_if=gre1


function __test_basic_gre() {
    local gretype=$1
    local ip_src=$2
    local ip_dst=$3
    local ex=""

    ip link del $tun_if >/dev/null 2>&1
    [ "$gretype" == "ip6gretap" ] && ex="-6"
    ip $ex link add $tun_if type $gretype external
    [ $? -ne 0 ] && err "Failed to create $gretype interface" && return 1

    ip -d link show $tun_if
    ip link set dev $tun_if up

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ifconfig $NIC up
    ip neigh add $ip_dst lladdr e4:11:22:11:55:55 dev $NIC

    reset_tc $REP $NIC $tun_if

    start_check_syndrome

    title "    - encap"
    tc_filter add dev $REP protocol ip ingress prio 1 \
                flower skip_sw \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                action tunnel_key set \
                    src_ip $ip_src \
                    dst_ip $ip_dst \
                    tos 0x30 \
                    ttl 63 \
                    id 100 \
                    nocsum \
                action mirred egress redirect dev $tun_if

    title "    - decap"
    tc_filter add dev $tun_if protocol ip ingress prio 2 \
                flower \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                        enc_src_ip $ip_dst \
                        enc_dst_ip $ip_src \
                        enc_key_id 100 \
                action tunnel_key unset \
                action mirred egress redirect dev $REP
    tc_filter show dev $tun_if ingress prio 2 | grep -q -w in_hw || err "Decap rule not in hw"

    check_syndrome

    reset_tc $REP $NIC $tun_if
    ip neigh del $ip_dst lladdr e4:11:22:11:55:55 dev $NIC
    ip addr flush dev $NIC
    ip link del $tun_if
}

function test_basic_gre_ipv4() {
    title "Testing IPv4"
    __test_basic_gre gretap 20.1.11.1 20.1.12.1
}

function test_basic_gre_ipv6() {
    title "Testing IPv6"
    __test_basic_gre ip6gretap \
        2001:0db8:85a3::8a2e:0370:7334 \
        2001:0db8:85a3::8a2e:0370:7335
}


config_sriov
enable_switchdev
test_basic_gre_ipv4
test_basic_gre_ipv6
check_kasan
test_done
