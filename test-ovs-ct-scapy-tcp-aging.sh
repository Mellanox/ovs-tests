#!/bin/bash
#
# Test OVS CT aging
# Test conntrack aging before OVS aging
# Expected result not get list_del corruption.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

function test_ct_aging() {
    if ! sysctl -a |grep net.netfilter.nf_flowtable_tcp_timeout >/dev/null 2>&1 ; then
        fail "Cannot set conntrack offload aging - missing net.netfilter.nf_flowtable_tcp_timeout"
    fi
}

function set_ct_aging() {
    local timeout=$1
    sysctl -w net.netfilter.nf_flowtable_tcp_timeout=$timeout || err "Failed setting tcp timeout"
}


test_ct_aging
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
    pkill -9 iperf3
    set_ct_aging 30 30 &>/dev/null
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
    ovs-ofctl add-flow br-ovs in_port=$REP,dl_type=0x0806,actions=drop
    ovs-ofctl add-flow br-ovs in_port=$REP2,dl_type=0x0806,actions=drop

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
}

function run() {
    title "Test OVS CT aging"
    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    proto="tcp"
    config_ovs $proto
    set_ct_aging 10 10
    fail_if_err

    t=5
    echo "run traffic tcp handshake"
    scpytcp

    if !  cat /proc/net/nf_conntrack |grep 7.7.7 |grep HW >/dev/null 2>&1 ; then
        err "TCP connection is not offloaded"
        return
    fi

    echo waitng for offload aging
    sleep 12

    if !  cat /proc/net/nf_conntrack |grep 7.7.7 |grep ASSURED >/dev/null 2>&1 ; then
        err "TCP connection is not in software"
        return
    fi

    echo waiting for software aging
    sleep 10

    if  cat /proc/net/nf_conntrack |grep 7.7.7 >/dev/null 2>&1 ; then
        err "Connection was not aged - still exists"
        return
    fi

}


run
echo clean
ovs-vsctl del-br br-ovs

test_done
