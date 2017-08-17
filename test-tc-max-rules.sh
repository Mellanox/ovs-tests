#!/bin/bash
#
# Test max rules in skip_sw and skip_hw on single port.
# Test max rules in 2 ports.
#
# Bug SW #900706: Adding 42K flows results in a fw error

NIC=${1:-ens5f0}
NIC2=${2:-ens5f1}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

CASE_SKIP=${CASE_SKIP:-skip_hw skip_sw}
CASE_COUNT=${CASE_COUNT:-30*1024 64*1024-16}
CASE_INDEX=${CASE_INDEX:-0 1}
TIMEOUT=${TIMEOUT:-30s}


function tc_batch() {
    timeout $TIMEOUT sh $my_dir/tc_batch.sh $@
    rc=$?
    if [ $rc == "0" ]; then
        success
    elif [ $rc == "124" ]; then
        err "Timed out after $TIMEOUT"
    else
        err
    fi
    return $rc
}

function do_test1() {
    for _nic in $NIC $NIC2; do
        # in case user has only one NIC
        if [[ "$_nic" == "" ]]; then
            continue
        fi
        for skip in $CASE_SKIP; do
            for num in $CASE_COUNT; do
                ((num=num))
                # if set_index == 1, all filters share the same action
                for index in $CASE_INDEX; do
                    title "Testing $num rules $skip $_nic set_index:$index"
                    tc_batch $num $skip $_nic $index || return
                    echo "cleanup"
                    reset_tc_nic $_nic
                done
            done
        done
    done
}

function do_test2() {
    ((num=64*1024-16))
    skip=skip_sw
    index=0
    title "Add both ports $num rules $skip set_index:$index"
    tc_batch $num $skip $NIC $index || return
    tc_batch $num $skip $NIC2 $index || return
    echo "cleanup"
    reset_tc_nic $NIC
    reset_tc_nic $NIC2
}


do_test1
do_test2
reset_tc_nic $NIC
reset_tc_nic $NIC2
test_done
