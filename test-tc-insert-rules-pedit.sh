#!/bin/bash
#
# Bug SW #1170023: deleting a flow rule with multiple vport destinations triggers FW error
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4


function tc_filter() {
    eval2 tc filter $@ && success
}

function test_basic_header_rewrite() {
    title "Add basic pedit rule on representor"
    reset_tc_nic $REP
    tc_filter add dev $REP protocol ip parent ffff: prio 1 \
        flower skip_sw ip_proto icmp \
        action pedit ex munge eth dst set 20:22:33:44:55:66 \
        pipe action mirred egress redirect dev $REP
}

function test_basic_header_rewrite_ip_icmp() {
    title "Add basic pedit rule on representor proto icmp pedit ip"
    # [342371.556405] can't offload re-write of ip proto 1
    # fix commit: [342371.556405] can't offload re-write of ip proto 1
    reset_tc_nic $REP
    tc_filter add dev $REP protocol ip parent ffff: prio 1 \
        flower skip_sw ip_proto icmp \
        action pedit ex munge ip dst set 7.7.7.2 \
        pipe action mirred egress redirect dev $REP
    dmesg | tail -n10 | grep "can't offload re-write"
}

function test_complex_header_rewrite_add1() {
    title "Add complex (macs, ttl add) pedit rule rep->nic"
    # EXCEED_LIM          | 0x2EDCC3 |  alloc_modify_header_context: actions number exceeds HW limit
    reset_tc_nic $REP
    tc_filter add dev $REP protocol ip parent ffff: prio 2 \
        flower skip_sw dst_mac aa:bb:cc:dd:ee:ff ip_proto tcp ip_ttl 40/ff dst_ip 7.7.7.3 \
        action pedit ex \
            munge ip ttl add 0xff \
            munge eth src set aa:ba:cc:dd:ee:fe \
            munge eth dst set aa:b7:cc:dd:ee:fe pipe \
        action mirred egress redirect dev $NIC
    reset_tc_nic $REP
}

function test_complex_header_rewrite_add2() {
    title "Add complex (macs, ips, ttl add) pedit rule rep->nic"
    # EXCEED_LIM          | 0x2EDCC3 |  alloc_modify_header_context: actions number exceeds HW limit
    reset_tc_nic $REP
    tc_filter add dev $REP protocol ip parent ffff: prio 2 \
        flower skip_sw dst_mac aa:bb:cc:dd:ee:ff ip_proto tcp ip_ttl 40/ff dst_ip 7.7.7.3 \
        action pedit ex \
            munge ip ttl add 0xff \
            munge ip dst set 1.1.1.2 \
            munge ip src set 1.1.1.2 \
            munge eth src set aa:ba:cc:dd:ee:fe \
            munge eth dst set aa:b7:cc:dd:ee:fe pipe \
        action mirred egress redirect dev $NIC
    reset_tc_nic $REP
}

function test_complex_header_rewrite_set() {
    title "Add complex (macs, ips, ttl set) pedit rule rep->nic"
    # EXCEED_LIM          | 0x2EDCC3 |  alloc_modify_header_context: actions number exceeds HW limit
    reset_tc_nic $REP
    tc_filter add dev $REP protocol ip parent ffff: prio 2 \
        flower skip_sw dst_mac aa:bb:cc:dd:ee:ff ip_proto tcp ip_ttl 40/ff dst_ip 7.7.7.3 \
        action pedit ex \
            munge ip ttl set 0xff \
            munge ip dst set 1.1.1.2 \
            munge ip src set 1.1.1.2 \
            munge eth src set aa:ba:cc:dd:ee:fe \
            munge eth dst set aa:b7:cc:dd:ee:fe pipe \
        action mirred egress redirect dev $NIC
    reset_tc_nic $REP
}


start_check_syndrome
enable_switchdev

test_basic_header_rewrite
test_basic_header_rewrite_ip_icmp
test_complex_header_rewrite_add1
test_complex_header_rewrite_add2
test_complex_header_rewrite_set

title "Check log"
check_kasan
check_syndrome
test_done
