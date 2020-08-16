#!/bin/bash
#
# Bug SW #1334271: Syndrome 0xd5ef2 when sending fragmented packets
#
# Currently we do not support offloading of frag first/later so verify this.
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov
enable_switchdev
REP=`get_rep 0`
if [ -z "$REP" ]; then
    fail "Missing rep $rep"
fi

function test_tc_filter() {
    local a
    local err
    local opnotsupp

    a=`eval tc filter $@ 2>&1`
    err=$?
    [ -n "$a" ] && echo $a

    echo "$a" | grep -q "Operation not supported" && true || false
    opnotsupp=$?

    if [ $err != 0 ] && [ $opnotsupp == 0 ]; then
        success $reason
    else
        err $reason
    fi
}


start_check_syndrome
reason="Expected to fail with reason EOPNOTSUPP"

title "Test fragfirst rule"
reset_tc $NIC
test_tc_filter add dev $NIC protocol ip parent ffff: flower skip_sw ip_flags firstfrag \
    dst_mac e4:11:22:11:4a:51 src_mac e4:11:22:11:4a:50 action drop

title "Test nofragfirst rule"
reset_tc $NIC
test_tc_filter add dev $NIC protocol ip parent ffff: flower skip_sw ip_flags nofirstfrag \
    dst_mac e4:11:22:11:4a:51 src_mac e4:11:22:11:4a:50 action drop

reset_tc $NIC
check_syndrome
test_done
