#!/bin/bash
#
#
# This test creates qdisc/block with multiple chains and verifies that
# qdisc/block can be safely removed while traffic matching filters on the
# classifiers is running.

VETH0=${1:-veth0}
VETH1=${2:-veth1}
my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_iperf_common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"
let NUM_PRIO=100
let PRIO_PER_CHAIN=$NUM_PRIO/5
let FIRST_PORT=50000
let LAST_PORT=$FIRST_PORT+$NUM_PRIO-1
RATE=1000000
MAX_TIME=1000
num_iter=3

function run_test() {
    local iteration=$1
    let max_chain=NUM_PRIO/PRIO_PER_CHAIN-1
    let last_prio=$PRIO_PER_CHAIN+1
    let total_filters=0

    title "Iteration $iteration"

    # Create max_chain+1 chains with PRIO_PER_CHAIN protos on each and add one
    # goto filter per chain
    port=$FIRST_PORT
    for chain in $(seq 0 $max_chain); do
        for prio in $(seq 1 $PRIO_PER_CHAIN); do
            add_drop_rule $VETH0 $chain $prio 1 $IP1 $port
            ((port=port+1))
            ((total_filters=total_filters+1))
        done
        if ((chain>0)); then
            let prev_chain=$chain-1
            tc_filter add dev $VETH0 protocol ip ingress chain $prev_chain prio $last_prio flower skip_hw dst_ip $IP1 action goto chain $chain
            ((total_filters=total_filters+1))
        fi
    done
    sleep 10
    check_filters_traffic $VETH0 $total_filters

    # Qdisc deletion releases reference to block, which in turn flushes all
    # chains on the block.
    tc qdisc del dev $VETH0 ingress
    tc qdisc add dev $VETH0 ingress

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
