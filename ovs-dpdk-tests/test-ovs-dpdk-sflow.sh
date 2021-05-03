#!/bin/bash
#
# Test OVS-DPDK sFlow
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
. $my_dir/../common.sh
. $my_dir/common-dpdk.sh

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

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    cleanup_e2e_cache
}
trap cleanup EXIT

function add_sflow_port() {
    SFLOW_SAMPLING=$1

    title "create sFlow"
    ovs-vsctl -- --id=@sflow create sflow agent=\"$SFLOW_AGENT\" \
              target=\"$SFLOW_TARGET:$SFLOW_PORT\" header=$SFLOW_HEADER \
              sampling=$SFLOW_SAMPLING polling=10 \
              -- set bridge br-phy sflow=@sflow

    ovs-vsctl list sflow
}

function config() {
    title "setup ovs"

    start_clean_openvswitch
    config_simple_bridge_with_rep 2
    config_ns ns0 $VF $IP1
    config_ns ns1 $VF2 $IP2
}

function run() {
    title "Test OVS sFlow"
    local file=/tmp/sflow.txt
    local t=10
    interval=$1

    ssh2 $SFLOW_TARGET timeout $((t+2)) sflowtool -p $SFLOW_PORT \
        -L localtime,srcIP,dstIP > $file&
    sleep 1

    title "run ping for $t seconds"
    ip netns exec ns0 ping $IP2 -q -i $interval -w $t

    wait

    if grep $IP1 $file | grep $IP2 > /dev/null; then
        success2 "get the expected IP addresses: $IP1, $IP2"
    else
        err "fail to get the expected IP addresses"
    fi

    #
    # If packet interval is 0.1, send 10 seconds, the total packet
    # number is 10 / 0.1 * 2 = 200, (REP and REP2)
    # The sampling rate is 1/10, so we expect to receive 20 sFlow packets.
    #
    n=$(awk 'END {print NR}' $file)
    expected=$(echo $t/$interval*2/$SFLOW_SAMPLING | bc)
    if (( n >= expected - 5 && n <= expected + 15 )); then
        success2 "get $n packets, expected $expected"
    else
        err "get $n packets, expected $expected"
    fi
    check_dpdk_offloads $IP1

    ovs-vsctl clear bridge br-phy sflow
}

config
add_sflow_port 10
run 0.1
add_sflow_port 1
run 1
start_clean_openvswitch
test_done
