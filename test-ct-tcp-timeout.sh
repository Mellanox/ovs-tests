#!/bin/bash
#
# Test CT tcp time_wait & last_ack timeout
#
# On multiple conntrack conns some are not aged out according to configured ct timeouts.
#
# [MLNX OFED] Bug SW #3053842: CT connections are not aged out
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

IP="7.7.7.1"
IP2="7.7.7.2"

function __test_ct_tcp_timeout() {
    if ! sysctl -a |grep net.netfilter.nf_conntrack_tcp_timeout_time_wait >/dev/null 2>&1 ; then
        fail "Cannot set ct tcp timeout time wait"
    fi
    if ! sysctl -a |grep net.netfilter.nf_conntrack_tcp_timeout_last_ack >/dev/null 2>&1 ; then
        fail "Cannot set ct tcp timeout last ack"
    fi
}

function get_tcp_timeout_param() {
    local param=$1
    sysctl net.netfilter | grep nf_conntrack_tcp_timeout_$param | cut -f2 -d '='
}

function set_tcp_timeout_param() {
    local param=$1
    local timeout=$2
    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_$param=$timeout || err "Failed to set tcp_timeout_$param=$timeout"
}

__test_ct_tcp_timeout

TIMEOUT=15
DEFAULT_TIMEOUT_TIME_WAIT=`get_tcp_timeout_param time_wait`
DEFAULT_TIMEOUT_LAST_ACK=`get_tcp_timeout_param last_ack`

# pre config
config_sriov 2
enable_switchdev
require_interfaces REP REP2
unbind_vfs
bind_vfs

function cleanup() {
    killall -q netserver netperf
    conntrack -F
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    ovs_clear_bridges
    set_tcp_timeout_param time_wait $DEFAULT_TIMEOUT_TIME_WAIT
    set_tcp_timeout_param last_ack $DEFAULT_TIMEOUT_LAST_ACK
}
trap cleanup EXIT

function config() {
    cleanup
    conntrack -F
    config_vf ns0 $VF $REP $IP
    config_vf ns1 $VF2 $REP2 $IP2
    config_ovs
    add_openflow_rules
    title "Setting both TCP LAST_ACK & TIME_WAIT to $TIMEOUT"
    set_tcp_timeout_param time_wait $TIMEOUT
    set_tcp_timeout_param last_ack $TIMEOUT
}

function config_ovs() {
    title "Config OvS"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP -- set interface $REP ofport_request=1
    ovs-vsctl add-port br-ovs $REP2 -- set interface $REP2 ofport_request=2
    ovs-vsctl show
}

function add_openflow_rules() {
    title "Adding openflow rules"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk, actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+new, actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=-new, actions=normal"
    ovs-ofctl dump-flows br-ovs --color
}

function run_traffic() {
    title "Running Traffic"

    ip netns exec ns0 netserver -L $IP || err "Failed to start netserver"

    for i in `seq 0 5`; do
        ip netns exec ns1 netperf -t TCP_CRR -H $IP -l 3  -- -r 1 -O "MIN_LAETENCY, MAX_LATENCY, MEAN_LATENCY, P90_LATENCY, P99_LATENCY ,P999_LATENCY,P9999_LATENCY,STDDEV_LATENCY ,THROUGHPUT ,THROUGHPUT_UNITS" || err "Failed to start netperf"
    done

    title "Sleeping for $TIMEOUT"
    sleep $TIMEOUT

    title "Verify CT TCP connections are aged out"
    conntrack -L -p tcp --src $IP2 --dst $IP | grep -q -E "(LAST_ACK|TIME_WAIT)"
    if [ $? -eq 0 ]; then
        conntrack -L -p tcp --src $IP2 --dst $IP | grep -E "(LAST_ACK|TIME_WAIT)" | tail -n3
        err "CT TCP connctions are not aged out"
    else
        success
    fi
}

config
run_traffic
trap - EXIT
cleanup
test_done
