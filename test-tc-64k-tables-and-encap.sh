#!/bin/bash
#
# Bug SW #3164606: After creating and deleting 65534 TC chains, new chains cannot be added
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

tmpfile="/tmp/bat"


#for cited bug to occur, vfs must be binded and encap must be set to basic
config_sriov 2
enable_switchdev
require_interfaces REP NIC
set_eswitch_encap basic
unbind_vfs
bind_vfs

function cleanup() {
    reset_tc $REP
    rm -f $tmpfile
}
trap cleanup EXIT

function run() {
    local chains=4
    local prios=17000
    local chain
    local prio
    local n

    title "Testing creating 64K flow tables (by adding 64K rules)"

    echo "create batch file $tmpfile"
    for((chain = 1; chain <= $chains; chain++)); do
        for((prio = 1; prio <= $prios; prio++)); do
            echo filter add dev $REP ingress chain $chain prio $prio flower skip_sw action mirred egress redirect dev $REP2
        done
    done > $tmpfile

    echo "first phase add"
    tc -b $tmpfile || { err "failed adding first phase rules"; return; }

    n=`tc filter show dev $REP ingress | grep -c handle`
    echo "first phase add done, filter num: $n"

    echo "first phase delete"
    reset_tc $REP

    echo "second phase add"
    for((chain = 1; chain <= 50; chain++)); do
        tc filter add dev $REP ingress chain $chain flower skip_sw action mirred egress redirect dev $REP2 || { err "failed adding second phase rules"; return; }
    done

    n=`tc filter show dev $REP ingress | grep -c handle`
    echo "second phase add done, filter num: $n"

    success
}

cleanup
run

trap - EXIT
cleanup
test_done
