#!/bin/bash
#
# Test max rules in skip_sw and skip_hw on single port.
# Test max rules in 2 ports.
#
#  #900706: Adding 42K flows results in a fw error
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh

CASE_NIC=${CASE_NIC:-$NIC}
CASE_SKIP=${CASE_SKIP:-skip_sw}
CASE_COUNT=${CASE_COUNT:-64*1024-100}
CASE_INDEX=${CASE_INDEX:-0 1}
TIMEOUT=${TIMEOUT:-5m}
CASE_TWO_PORTS=${CASE_TWO_PORTS:-1}
# MODE: switchdev, legacy, nic
CASE_MODE=${CASE_MODE:-switchdev}


function get_used_mem() {
    vmstat -s | grep -i "used memory" | awk {'print $1'}
}

function tc_batch() {
    local num=$1
    memused1=`get_used_mem`
    timeout $TIMEOUT bash $my_dir/tc_batch.sh $@
    rc=$?
    if [ $rc == "0" ]; then
        success
        memused2=`get_used_mem`
        mem_per_rule=`echo "scale=2; ($memused2-$memused1)/$num" | bc`
        echo "avg mem per rule is $mem_per_rule kb"
    elif [ $rc == "124" ]; then
        err "Timed out after $TIMEOUT"
    else
        err
    fi
    return $rc
}

function __test_max_rules() {
    for _nic in $CASE_NIC; do
        for skip in $CASE_SKIP; do
            for num in $CASE_COUNT; do
                ((num=num))
                # if set_index == 1, all filters share the same action
                for index in $CASE_INDEX; do
                    title "Testing $num rules $skip $_nic set_index:$index"
                    tc_batch $num $skip $_nic $index || return
                    echo "cleanup"
                    reset_tc $_nic
                done
            done
        done
    done
}

function test_max_rules_switchdev() {
    title "Test max rules switchdev"
    for _nic in $CASE_NIC; do
        config_sriov 2 $_nic
        enable_switchdev $_nic
    done
    __test_max_rules
}

function test_max_rules_legacy() {
    title "Test max rules legacy"
    for _nic in $CASE_NIC; do
        config_sriov 2 $_nic
        enable_legacy $_nic
        reset_tc $_nic
    done
    __test_max_rules
}

function test_max_rules_nic_mode() {
    title "Test max rules nic mode"
    for _nic in $CASE_NIC; do
        config_sriov 0 $_nic
    done
    __test_max_rules
    config_sriov 2 $_nic
}

function test_max_rules_two_ports() {
    ((num=64*1024-100))
    skip=skip_sw
    index=0
    config_sriov 2 $NIC
    enable_switchdev $NIC
    config_sriov 2 $NIC2
    enable_switchdev $NIC2
    title "Add both ports $num rules $skip set_index:$index"
    tc_batch $num $skip $NIC $index || return
    tc_batch $num $skip $NIC2 $index || return
    echo "cleanup"
    reset_tc $NIC
    reset_tc $NIC2
}

if [ "$CASE_MODE" == "switchdev" ]; then
    test_max_rules_switchdev
elif [ "$CASE_MODE" == "legacy" ]; then
    test_max_rules_legacy
elif [ "$CASE_MODE" == "nic" ]; then
    test_max_rules_nic_mode
else
    fail "Unknown case mode '$CASE_MODE'"
fi
[ $CASE_TWO_PORTS == "1" ] && test_max_rules_two_ports
reset_tc $NIC
reset_tc $NIC2
test_done
