#!/bin/bash
#
# Test to check if filter printed in_hw but its action printed not_in_hw. 
#
#
#filter parent ffff: protocol arp pref 8 flower chain 0 handle 0x1 
#  eth_type arp
#  in_hw in_hw_count 1
#        action order 1: gact action drop
#         random type none pass val 0
#         index 4 ref 1 bind 1
#        not_in_hw
#        used_hw_stats delayed
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


title "Test tc filter in_hw and action not_in_hw"
reset_tc $NIC

tc_filter replace dev $NIC protocol 0x806 parent ffff: prio 8 flower action drop
tc filter show dev $NIC ingress

count=`tc filter show dev $NIC ingress | grep -o -w -e "[a-z_]*in_hw" | uniq | wc -l`

if [ $count -ne 1 ]; then
    err "Mix in_hw and not_in_hw"
fi

reset_tc $NIC
test_done
