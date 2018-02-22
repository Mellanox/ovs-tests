#!/bin/bash
#
#

NIC=${1:-ens5f0}
FILTER=${FILTER}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function tc_filter() {
    eval2 tc filter $@ && success || err
}

# header rewrite cx5 only
function test_basic_header_rewrite() {
    not_relevant_for_cx4

    title "Add pedit rule on representor"
    reset_tc_nic $REP
    tc_filter add dev $REP protocol ip parent ffff: \
        flower skip_sw ip_proto icmp \
        action pedit ex munge eth dst set 20:22:33:44:55:66 \
        pipe action mirred egress redirect dev $REP
    reset_tc_nic $REP
}

enable_switchdev
test_basic_header_rewrite
check_kasan
test_done
