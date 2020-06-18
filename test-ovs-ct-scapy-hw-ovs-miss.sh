#!/bin/bash
#
# Test correct OVS CT miss from hardware (set skb ext) straight to ovs (read skb ext).
# This happens as the original direction (in_port(REP0)) +est rule will come after the tuple
# is established and offloaded, which in this case on the reply direction.
#
# Bug SW #2114608: [Upstream][CT] Traffic not offloaded with CT UDP
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

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
    local proto=$1
    zone=30

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs "arp, actions=normal"

    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=+trk,nw_dst=$IP1,$proto actions=drop"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=+trk,nw_dst=$IP2,$proto actions=drop"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=+trk,nw_dst=255.255.255.255 actions=drop"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_dst=255.255.255.255 actions=drop"

    ovs-ofctl add-flow br-ovs "table=0, ip,$proto,ct_state=-trk actions=ct(table=1, zone=$zone)"
    ovs-ofctl add-flow br-ovs "table=1, ip,$proto,ct_state=+trk+new actions=ct(commit, zone=$zone),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,$proto,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color
}

function randport() {
    echo $((RANDOM%60000 + 1000))
}

sport=`randport`
dport=`randport`

function run_python_ns() {
    local ns=$1; shift;

    echo "[$ns] python: $@"
    ip netns exec $ns python -c "$@"
}

function scpyudp() {
    echo "running udp scapy: [ns0] $IP1:$sport -> [ns1] $IP2:$dport"

    #------------------ DATA --->  --------------------

    echo "packet, orig 1"
    run_python_ns ns0 "from scapy.all import *; send(IP(src=\"$IP1\",dst=\"$IP2\")/UDP(sport=$sport,dport=$dport)/\"A1\")"
    echo "packet, orig 2"
    run_python_ns ns0 "from scapy.all import *; send(IP(src=\"$IP1\",dst=\"$IP2\")/UDP(sport=$sport,dport=$dport)/\"A2\")"
    echo "packet, orig 3"
    run_python_ns ns0 "from scapy.all import *; send(IP(src=\"$IP1\",dst=\"$IP2\")/UDP(sport=$sport,dport=$dport)/\"A3\")"

    #------------------ DATA <---  --------------------

    echo "packet, reply"
    run_python_ns ns1 "from scapy.all import *; send(IP(src=\"$IP2\",dst=\"$IP1\")/UDP(sport=$dport,dport=$sport)/\"B1\")"
    echo "packet, reply"
    run_python_ns ns1 "from scapy.all import *; send(IP(src=\"$IP2\",dst=\"$IP1\")/UDP(sport=$dport,dport=$sport)/\"B2\")"

    #------------------ DATA --->  --------------------

    echo "packet, orig"
    run_python_ns ns0 "from scapy.all import *; send(IP(src=\"$IP1\",dst=\"$IP2\")/UDP(sport=$sport,dport=$dport)/\"C1\")"
    echo "packet, orig"
    run_python_ns ns0 "from scapy.all import *; send(IP(src=\"$IP1\",dst=\"$IP2\")/UDP(sport=$sport,dport=$dport)/\"C2\")"

    #------------------ DATA <---  --------------------

    echo "packet, reply"
    run_python_ns ns1 "from scapy.all import *; send(IP(src=\"$IP2\",dst=\"$IP1\")/UDP(sport=$dport,dport=$sport)/\"D1\")"
    echo "packet, reply"
    run_python_ns ns1 "from scapy.all import *; send(IP(src=\"$IP2\",dst=\"$IP1\")/UDP(sport=$dport,dport=$sport)/\"D2\")"

    #------------------ END ---------------------------
}


function run() {
    title "Test OVS CT UDP miss from hardware to ovs"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    proto="udp"
    config_ovs $proto

    # needed for scapy
    ip netns exec ns0 ip link set lo up
    ip netns exec ns1 ip link set lo up

    title "run traffic once"
    scpyudp

    title "check offloaded in zone $zone"
    cat /proc/net/nf_conntrack | grep --color -i offload | grep -i $IP1 | grep -i $IP2 | grep "zone=$zone" || err "tuple not offloaded"

    ovs_dump_tc_flows --names
    ovs_dump_tc_flows --names | grep -q "ct(.*commit.*)" || err "Expected ct commit action"
    ovs_dump_tc_flows --names | grep "in_port($REP)" | grep -q "ct_state(.*+est.*)" || err "Expected established match on $REP"
    ovs_dump_tc_flows --names | grep "in_port($REP2)" | grep -q "ct_state(.*+est.*)" || err "Expected established match on $REP2"
    ovs_dump_flows --names | grep "recirc_id(0)" | grep "ct_state(.*+trk.*)" && err "Tracked packet on recirc_id(0) - incorrect restore"

    title "check for offloaded - no traffic on rep"
    timeout 5 tcpdump -qnnei $REP -c 1 $proto &
    pid1=$!

    title "run traffic 2nd time - should be offloaded"
    scpyudp

    test_no_traffic $pid1

    ovs-vsctl del-br br-ovs
}

function test_no_traffic() {
    local pid=$1
    wait $pid
    rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed"
    fi
}

run
test_done
