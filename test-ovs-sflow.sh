#!/bin/bash
#
# Test OVS sFlow
#
# The test setup is exactly same as this one:
#   http://docs.openvswitch.org/en/latest/howto/sflow/
# sflowtool must be installed on Monitoring host to receive the sflow.
# You can download it from "from git@github.com:sflow/sflowtool.git".
# sFlow will create a UDP connection to send the sampled packets.
# So SFLOW_AGENT on Host 1 should be able to create a UDP connection
# to SFLOW_TARGET on Monitoring Host. It doesn't matter if SFLOW_AGENT
# is mellanox port or not.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

#
# It is eth1 on Host 1 in the diagram of
#   http://docs.openvswitch.org/en/latest/_images/sflow.png
#
SFLOW_AGENT=${SFLOW_AGENT:-$1}

# IP address of eth0 on Monitoring Host
SFLOW_TARGET=${REMOTE_SERVER:-$2}

# default port number
SFLOW_PORT=6343

# trunc size
SFLOW_HEADER=96

# sample rate, 1/10
SFLOW_SAMPLING=10

IP1="7.7.7.1"
IP2="7.7.7.2"

log "Remote server $REMOTE_SERVER"
on_remote true || fail "Remote command failed"
on_remote which sflowtool || \
    fail "sflowtool missing on remote host $REMOTE_SERVER"
on_remote pkill sflowtool

config_sriov 2
enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs
reset_tc $REP
reset_tc $REP2

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function config_ovs() {
    title "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    title "create sFlow"
    ovs-vsctl -- --id=@sflow create sflow agent=$SFLOW_AGENT \
              target=\"$SFLOW_TARGET:$SFLOW_PORT\" header=$SFLOW_HEADER \
              sampling=$SFLOW_SAMPLING polling=10 \
              -- set bridge br-ovs sflow=@sflow

    ovs-vsctl list sflow
}

function run() {
    title "Test OVS sFlow"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    local file=/tmp/sflow.txt
    local t=10
    local interval=0.1

    config_ovs

    ssh2 $SFLOW_TARGET timeout $((t+2)) sflowtool -p $SFLOW_PORT \
        -L localtime,srcIP,dstIP > $file&
    sleep 1

    title "run ping for $t seconds"
    ip netns exec ns0 ping $IP2 -q -i $interval -w $t &
    pk1=$!
    sleep 0.5

    wait $pk1 &>/dev/null

    if grep $IP1 $file | grep $IP2 > /dev/null; then
        success2 "get the expected IP addresses: $IP1, $IP2"
    else
        err "fail to get the expected IP addresses"
    fi

    #
    # The packet interval is 0.1, send 10 seconds, the total packet
    # number is 10 / 0.1 * 2 = 200, (REP and REP2)
    # The sampling rate is 1/10, so we expect to receive 20 sFlow packets.
    #
    n=$(awk 'END {print NR}' $file)
    expected=$(echo $t/$interval*2/$SFLOW_SAMPLING | bc)
    if (( n >= expected - 10 && n <= expected + 10 )); then
        success2 "get $n packets, expected $expected"
    else
        err "get $n packets, expected $expected"
    fi

    count=$(ovs_dump_tc_flows | grep 0x0800 | grep sFlow | wc -l)
    if (( count != 2 )); then
        ovs_dump_tc_flows --names
        err "No sample offloaded rules"
    fi

    ovs-vsctl del-br br-ovs
}

run
test_done
