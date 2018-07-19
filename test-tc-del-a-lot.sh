#!/bin/bash
#
# Test inserting a lot of mirred rules and deleting them in parallel.
#
#
NIC=${1:-ens2f0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

CASE_COUNT=${CASE_COUNT:-100}
TIMEOUT=${TIMEOUT:-5m}

enable_switchdev
REP=veth0

function cleanup() {
    for i in `seq 0 7`; do
        ip link del veth$i &> /dev/null
    done
    reset_tc_nic $NIC
}

function tc_show() {
    local nic=$1
    tc filter show dev $nic ingress &>/dev/null
}

function tc_delete() {
    local nic=$1

    # reset ingress
    tc qdisc del dev $nic ingress &>/dev/null || true

    # add ingress
    tc qdisc add dev $nic ingress &>/dev/null
}

function tc_batch() {
    local num=$1
    local nic=$2
    local rep=$3
    local t=$4
    local prio=$5
    local file=/tmp/mirred_batch_${t}

    while ((num--)); do
        dmac="aa:bb:cc:$(((num/10000)%100)):$(((num/100)%100)):$((num%100))"
        smac="aa:bb:cc:dd:$prio:$t"
        echo "filter add dev $nic protocol ip ingress prio $prio flower dst_mac $dmac src_mac $smac action mirred egress redirect dev $rep"
    done > $file

    timeout $TIMEOUT tc -force -b $file &>/dev/null
    rc=$?
    if [ $rc == "0" ]; then
        : pass
    elif [ $rc == "124" ]; then
        err "tc_batch timed out after $TIMEOUT"
    else
        # we dont care. we delete qdisc in parallel so we could fail but the
        # purpose of the test is to cause a crash.
        rc=0
    fi

    rm -fr $file
    return $rc
}

function do_test1() {
    title "Test multiple dels/adds/show in parallel"

    modprobe -rv act_mirred
    tc filter add dev $NIC protocol ip prio 1 ingress flower skip_hw action mirred egress redirect dev $REP
    tc filter del dev $NIC prio 1 ingress

    for x in `seq 20`; do
        sleep $x && tc_show $NIC&
        sleep $x && tc_show $NIC&
    done

    for t in `seq $CASE_COUNT`; do
        num=$((RANDOM%50 + 1))
        prio=$((RANDOM%5+1))
        tc_batch $num $NIC $REP $t $prio&
    done
    for t in `seq $((CASE_COUNT*2))`; do
        sl=$((RANDOM%20+1))
        sleep $sl && tc_delete $NIC&
    done
    wait
}

cleanup

echo "setup veth"
ip link add veth0 type veth peer name veth1

do_test1
cleanup
check_kasan
test_done
