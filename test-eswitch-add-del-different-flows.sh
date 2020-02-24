#!/bin/bash
#
# Test add and del flows at the same time
# 2. start adding rules in bg
# 3. sleep
# 4. start deleting rules
#
# Expected result: not to crash
#

NIC=${1:-ens5f0}

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

COUNT=5

function tc_filter() {
    eval2 tc filter $@ || fail
}

function add_rules() {
    echo "add rules"
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc_filter add dev $NIC1 protocol ip parent ffff: prio $i \
            flower skip_sw indev $NIC1 \
            src_mac e1:22:33:44:${num1}:$num2 \
            dst_mac e2:22:33:44:${num1}:$num2 \
            action drop
    done
}

function add_rules_vlan() {
    echo "add rules vlan"
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc_filter add dev $NIC1 protocol 802.1Q parent ffff: prio $i \
            flower skip_sw indev $NIC1 \
            src_mac e1:22:33:44:${num1}:$num2 \
            dst_mac e2:22:33:44:${num1}:$num2 \
            vlan_ethtype 0x800 \
            vlan_id 100 \
            action mirred egress redirect dev $REP
    done
}

function add_rules_vlan_drop() {
    echo "add rules vlan drop"
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc_filter add dev $NIC1 protocol 802.1Q parent ffff: prio $i \
            flower skip_sw indev $NIC1 \
            src_mac e1:22:33:44:${num1}:$num2 \
            dst_mac e2:22:33:44:${num1}:$num2 \
            vlan_ethtype 0x800 \
            vlan_id 100 \
            action drop
    done
}

function del_rules() {
    local count="$1"
    echo "del rules"
    for i in `seq $COUNT`; do
        num1=`printf "%02x" $((i / 100))`
        num2=`printf "%02x" $((i % 100))`
        tc_filter del dev $NIC1 parent ffff: prio $i
    done
}


for NIC1 in $NIC $rep ; do
    title "Test nic $NIC1"
    reset_tc $NIC1
    add_rules
    del_rules
    add_rules_vlan
    del_rules
    add_rules_vlan_drop
    del_rules
    echo "reset"
    reset_tc $NIC1
done

test_done
