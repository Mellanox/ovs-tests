#!/bin/bash
#
# Bug SW #1170023: deleting a flow rule with multiple vport destinations triggers FW error
#

NIC=${1:-ens5f0}
FILTER=${FILTER}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4


function tc_filter() {
    eval2 tc filter $@ && success || err
}

function test_basic_header_rewrite() {
    title "Add basic pedit rule on representor"
    reset_tc_nic $REP
    tc_filter add dev $REP protocol ip parent ffff: prio 1 \
        flower skip_sw ip_proto icmp \
        action pedit ex munge eth dst set 20:22:33:44:55:66 \
        pipe action mirred egress redirect dev $REP
}

function test_complex_header_rewrite() {
    title "Add complex (macs, ips, ttl) pedit rule on representor"
    reset_tc_nic $REP
    tc_filter add dev $REP protocol ip parent ffff: prio 2 \
        flower skip_sw dst_mac aa:bb:cc:dd:ee:ff ip_proto tcp ip_ttl 40/ff dst_ip 7.7.7.3 ip_flags nofrag \
        action pedit ex munge ip ttl add 0xff pipe \
        action pedit ex munge ip dst set 1.1.1.2 pipe \
        action pedit ex munge ip src set 1.1.1.2  pipe \
        action pedit ex munge eth src set aa:ba:cc:dd:ee:fe  pipe \
        action pedit ex munge eth dst set aa:b7:cc:dd:ee:fe  pipe  \
        action mirred egress redirect dev $NIC
    reset_tc_nic $REP
}


start_check_syndrome
enable_switchdev

test_basic_header_rewrite
test_complex_header_rewrite

check_kasan
check_syndrome
test_done
