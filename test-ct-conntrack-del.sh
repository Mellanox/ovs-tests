#!/bin/bash
#
# Test conntrack del (-D) of offloaded traffic
#
# Scrum Task #3385360: [CT] Support conntrack -D <tuple> on offloaded tuples
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
    ovs-vsctl del-br br-ovs &> /dev/null

    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function config_ovs() {
    local proto=$1

    echo "setup ovs"
    conntrack -F
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    # need to drop arp packets to allow scpy tcp traffic
    # otherwise, the server would reply with a TCP RST packet on SYN because
    # there is no TCP listener
    ovs-ofctl add-flow br-ovs "arp,actions=drop"

    # ct rules
    ovs-ofctl add-flow br-ovs "table=0, $proto,ct_state=-trk actions=ct(table=1,nat)"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color
}

function scpytcp() {
    local src=$IP1
    local dst=$IP2
    local sport=2001
    local dport=5201
    local ns1=ns0
    local ns2=ns1

    ip netns exec $ns1 ip link set lo up
    ip netns exec $ns2 ip link set lo up

    ip netns exec $ns1 python -c "from scapy.all import *; send(IP(src=\"$src\",dst=\"$dst\")/TCP(sport=$sport,dport=$dport,seq=100,flags='S'))"
    ip netns exec $ns2 python -c "from scapy.all import *; send(IP(src=\"$dst\",dst=\"$src\")/TCP(sport=$dport,dport=$sport,seq=101,ack=101,flags='SA'))"
    ip netns exec $ns1 python -c "from scapy.all import *; send(IP(src=\"$src\",dst=\"$dst\")/TCP(sport=$sport,dport=$dport,seq=101,ack=102,flags='A'))"
    ip netns exec $ns1 python -c "from scapy.all import *; send(IP(src=\"$src\",dst=\"$dst\")/TCP(sport=$sport,dport=$dport,seq=101,ack=102,flags='A')/\"A1\")"
    ip netns exec $ns1 python -c "from scapy.all import *; send(IP(src=\"$src\",dst=\"$dst\")/TCP(sport=$sport,dport=$dport,seq=103,ack=102,flags='A')/\"A2\")"
    ip netns exec $ns1 python -c "from scapy.all import *; send(IP(src=\"$src\",dst=\"$dst\")/TCP(sport=$sport,dport=$dport,seq=105,ack=102,flags='A')/\"A3\")"
}

function run() {
    title "Test conntrack util del on offloaded tuples"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    proto="tcp"
    config_ovs $proto
    fail_if_err

    t=5
    echo "run traffic tcp handshake and traffic"
    scpytcp

    sleep 2

    echo "checking if tuple was offloaded to hw"
    cat /proc/net/nf_conntrack |grep 7.7.7 |grep HW
    if !  cat /proc/net/nf_conntrack |grep 7.7.7 |grep HW >/dev/null 2>&1 ; then
        err "TCP connection is not offloaded"
        return
    fi

    echo "deleting tuples with src ip $IP1"
    conntrack -D -s $IP1

    title "check if connection was deleted"
    cat /proc/net/nf_conntrack | grep 7.7.7
    if cat /proc/net/nf_conntrack |grep 7.7.7 >/dev/null 2>&1 ; then
        err "TCP connection was not deleted"
        return
    fi
}


run
test_done
