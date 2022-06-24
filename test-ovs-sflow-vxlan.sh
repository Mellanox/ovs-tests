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
SFLOW_AGENT=lo

# IP address of eth0 on Monitoring Host
SFLOW_TARGET=127.0.0.1

# default port number
SFLOW_PORT=6343

# trunc size
SFLOW_HEADER=96

IP1="1.1.1.7"
IP2="1.1.1.8"

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

which sflowtool || fail "sflowtool is missing"
pkill sflowtool

config_sriov 2
enable_switchdev
require_interfaces REP
unbind_vfs
bind_vfs
reset_tc $REP

function cleanup() {
    ovs_conf_remove tc-policy &>/dev/null
    ip netns del ns0 2> /dev/null
    reset_tc $REP
    cleanup_remote_vxlan
}
trap cleanup EXIT

function config_ovs() {
    title "setup ovs"

    SFLOW_SAMPLING=$1

    start_clean_openvswitch
    ifconfig $NIC $LOCAL_TUN/24 up
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789

    title "create sFlow"
    ovs-vsctl -- --id=@sflow create sflow agent=\"$SFLOW_AGENT\" \
              target=\"$SFLOW_TARGET:$SFLOW_PORT\" header=$SFLOW_HEADER \
              sampling=$SFLOW_SAMPLING polling=10 \
              -- set bridge br-ovs sflow=@sflow

    ovs-vsctl list sflow
}

function verify_ovs() {
    count=$(ovs_dump_ovs_flows | grep 0x0800 | grep sFlow | wc -l)
    if (( count != 2 )); then
        ovs_dump_ovs_flows --names
        err "No ovs sample rules"
    fi
}

function verify_tc_policy_skip_hw() {
    count=$(ovs_dump_tc_flows | grep 0x0800 | grep sFlow | wc -l)
    if (( count != 2 )); then
        ovs_dump_tc_flows --names
        err "No tc sample rules"
    fi
}

function verify_tc_policy_none() {
    count=$(ovs_dump_offloaded_flows | grep 0x0800 | grep sFlow | wc -l)
    if (( count != 2 )); then
        ovs_dump_offloaded_flows --names
        err "No offloaded sample rules"
    fi
}

function run() {
    local file=/tmp/sflow.txt
    local t=10
    interval=$1

    timeout $((t+2)) sflowtool -p $SFLOW_PORT -L localtime,srcIP,dstIP > $file&
    sleep 1

    title "Ping for $t seconds"
    ip netns exec ns0 ping $IP2 -q -i $interval -w $t

    wait

    if grep $IP1 $file | grep $IP2 > /dev/null; then
        success2 "Found the expected IP addresses: $IP1, $IP2"
    else
        err "Cannot find the expected IP addresses"
    fi

    #
    # If packet interval is 0.001, send 10 seconds, the total packet number
    # is 10 / 0.001 * 2 = 20000, (REP and vxlan). If the sampling rate is 1/2,
    # we expect to receive 10000 sFlow packets.
    #
    n=$(awk 'END {print NR}' $file)
    expected=$(echo $t/$interval*2/$SFLOW_SAMPLING | bc)
    deviation=$((expected/10)) # 10% deviation

    str="Got $n packets, expected $expected"
    (( n >= expected - deviation && n <= expected + deviation )) && \
        success2 $str || err $str
}

config_vf ns0 $VF $REP $IP1
REMOTE=$IP2
config_remote_vxlan
start_clean_openvswitch

title "Test OVS sFlow without offload"
ovs_conf_remove hw-offload
ovs_conf_remove tc-policy
config_ovs 2
run 0.001
verify_ovs

title "Test OVS sFlow with tc-policy=skip_hw"
ovs_conf_set hw-offload true
ovs_conf_set tc-policy skip_hw
config_ovs 2
run 0.001
verify_tc_policy_skip_hw

title "Test OVS sFlow with tc-policy=none sampling-2"
ovs_conf_set hw-offload true
ovs_conf_set tc-policy none
config_ovs 2
run 0.001
verify_tc_policy_none

title "Test OVS sFlow with tc-policy=none sampling=1"
config_ovs 1
run 1
verify_tc_policy_none

ovs_conf_remove tc-policy
start_clean_openvswitch
test_done
