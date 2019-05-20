#!/bin/bash
#
# Test OVS CT icmp traffic
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

enable_switchdev_if_no_rep $REP
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

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4

    echo "[$ns] $vf ($ip) -> $rep"
    ifconfig $rep 0 up
    ip netns add $ns
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $ip/24 up
}

function run() {
    title "Test OVS CT ICMP"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl add-flow br-ovs in_port=$REP,dl_type=0x0806,actions=output:$REP2
    ovs-ofctl add-flow br-ovs in_port=$REP2,dl_type=0x0806,actions=output:$REP

    ovs-ofctl add-flow br-ovs "table=0, icmp,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, icmp,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, icmp,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color

    echo "sniff packets on $REP"
    timeout 2 tcpdump -qnnei $REP -c 6 'icmp' &
    pid=$!

    echo "run traffic"
    ip netns exec ns0 ping -q -c 10 -i 0.1 -w 2 $IP2 || err "Ping failed"

    echo "verify icmp tc rule"
    if tc filter show dev $REP ingress | grep -q "ip_proto icmp" ; then
        success
    else
        err "missing icmp tc rule"
    fi

    # test sniff timedout
    warn "Currently ICMP is not offloaded with CT so testing traffic is not offloaded so it will fail when is supported and update the test."
    wait $pid
    rc=$?
    if [[ $rc -eq 0 ]]; then
        success
    elif [[ $rc -eq 124 ]]; then
        err "Didn't expect offload"
    else
        err "Tcpdump failed"
    fi

    ovs-vsctl del-br br-ovs
}


run
test_done
