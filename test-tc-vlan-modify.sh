#!/bin/bash
#
# Task #1695125: Upstream 5.2: VLAN header rewrite
#
# Modify vlan id by tc-modify and pop+push
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_interfaces REP NIC

function run() {
    reset_tc $REP

    title "Add TC mirred rule for VLAN modify 10->11"
    tc_filter add dev $REP protocol 802.1q ingress prio 1 flower skip_sw \
        dst_mac e4:11:22:33:44:70 \
        vlan_id 10 \
        action vlan modify id 11 pipe \
        action mirred egress redirect dev $NIC
    reset_tc $REP

    title "Add TC mirred rule for VLAN pop+push 11"
    tc_filter add dev $REP protocol 802.1q ingress prio 1 flower skip_sw \
        dst_mac e4:11:22:33:44:70 \
        vlan_id 10 \
        action vlan pop pipe action vlan push id 11 pipe \
        action mirred egress redirect dev $NIC
    reset_tc $REP
}

run
test_done
