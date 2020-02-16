#!/bin/bash
#
# Test header rewrite of ttl from VF to uplink and from VF to VF.
#
# Bug SW #1366970: FW syndrome adding header rewrite rule of ttl and fwd to internal vport
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4


function test_header_rewrite_ttl_uplink() {
    title "Add complex (macs, ips, ttl add) pedit rule rep->nic"
    reset_tc $REP
    tc_filter_success add dev $REP protocol ip parent ffff: prio 2 \
        flower skip_sw dst_mac aa:bb:cc:dd:ee:ff ip_proto tcp ip_ttl 40/ff dst_ip 7.7.7.3 \
        action pedit ex \
            munge ip ttl add 0xff pipe \
        action mirred egress redirect dev $NIC
    reset_tc $REP
}

function test_header_rewrite_ttl_vport() {
    title "Add complex (macs, ips, ttl add) pedit rule rep->rep"
    # BAD_PARAM           | 0x3B7492 |  set_flow_table_entry: modify ipv4 ttl action in fdb can not forward to internal vport
    reset_tc $REP
    tc_filter_success add dev $REP protocol ip parent ffff: prio 2 \
        flower skip_sw dst_mac aa:bb:cc:dd:ee:ff ip_proto tcp ip_ttl 40/ff dst_ip 7.7.7.3 \
        action pedit ex \
            munge ip ttl add 0xff pipe \
        action mirred egress redirect dev $REP
    reset_tc $REP
}

start_check_syndrome
enable_switchdev

test_header_rewrite_ttl_uplink
test_header_rewrite_ttl_vport

title "Check log"
check_kasan
check_syndrome
test_done
