#!/bin/bash
#
# Test OVS CT UDP frag traffic with iperf3
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

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

function run() {
    title "Test OVS CT UDP frag"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color

    echo "run traffic"
    t=12
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf3 -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf3 -u -t $t -c $IP2 -l 16384 -b 10G &

    sleep 2
    pgrep iperf3 &>/dev/null || err "iperf3 failed"

    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 10 'udp' &
    pid=$!

    sleep $t
    pkill iperf3 &>/dev/null
    pkill iperf3 &>/dev/null
    wait $! 2>/dev/null

    # test sniff timedout
    wait $pid
    rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed"
    fi

    ovs-vsctl del-br br-ovs
}


run
test_done
