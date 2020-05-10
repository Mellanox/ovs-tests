#!/bin/bash
#
#
# This test verifies that new filters can be safely created and deleted while
# traffic matching these filters is running.

VETH0=${1:-veth0}
VETH1=${2:-veth1}
my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_iperf_common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"
let NUM_PRIO=60
let FIRST_PORT=50000
let LAST_PORT=$FIRST_PORT+$NUM_PRIO-1
RATE=1000000
MAX_TIME=1000
num_iter=3

function run_test() {
    local iteration=$1
    local chain=0
    local prio=1
    local handle=1

    title "Iteration $iteration"

    # Create NUM_PRIO filters on single proto instance
    for i in $(seq $FIRST_PORT $LAST_PORT); do
        add_drop_rule $VETH0 $chain $prio $handle $IP1 $i
        ((handle=handle+1))
    done
    sleep 2
    check_filters_traffic $VETH0 $NUM_PRIO

    ((handle=1))
    for i in $(seq $FIRST_PORT $LAST_PORT); do
        del_drop_rule $VETH0 $chain $prio $handle
        ((handle=handle+1))
    done
    check_num_filters $VETH0 0
    sleep 2
}

cleanup_veth $VETH0 $VETH1
setup_veth $VETH0 $IP1 $VETH1 $IP2

spawn_n_iperf_pairs $IP2 $FIRST_PORT $RATE $MAX_TIME $NUM_PRIO

for i in $(seq 1 $num_iter); do
    run_test $i
done

cleanup_iperf
cleanup_veth $VETH0 $VETH1
test_done
