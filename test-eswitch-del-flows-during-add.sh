#!/bin/bash
#
# Test add and del flows at the same time
# 2. start adding rules in bg
# 3. sleep
# 4. start deleting rules
#
# Expected result: not to crash
#

COUNT=2500
ADD_DEL_SLEEP=10

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev
rep=`get_rep 0`
if [ -z "$rep" ]; then
    fail "Missing rep $rep"
    exit 1
fi
reset_tc $NIC
reset_tc $rep

function add_rules() {
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc_filter add dev $rep protocol ip parent ffff: prio 1 handle $i \
            flower skip_sw \
            src_mac e1:22:33:44:${num1}:$num2 \
            dst_mac e2:22:33:44:${num1}:$num2 \
            action drop || return
    done
    echo "add rules done"
}

function del_rules() {
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc_filter del dev $rep protocol ip parent ffff: prio 1 handle $i flower || return
    done
    echo "del rules done"
}


title "start adding rules"
add_rules &
sleep $ADD_DEL_SLEEP
title "start deleting rules"
del_rules
reset_tc $rep

test_done
