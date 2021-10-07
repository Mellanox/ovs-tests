#!/bin/bash
#
# Test OVS CT fragmented traffic (ping over MTU) and verifies bytes count on frag=first rule
#
# Bug SW #2796010: Incorrect flow stats for IP fragments with CT

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    ip -all netns del
    ovs_clear_bridges
}
trap cleanup EXIT

function add_netns() {
    local ns=$1
    local ip=$2
    local peer=${ns}_peer
    local veth=${ns}_veth

    echo "Create namespace $ns, veths: hv $veth <-> ns $peer ($ip)"
    ip netns add $ns
    ip link del $veth &>/dev/null
    ip link add $veth type veth peer name $peer
    ip link set $veth up
    ip link set $peer netns $ns
    ip netns exec $ns ifconfig $peer $ip/24 mtu 1400 up
}

function run() {
    title "Test OVS CT frag byte count via ping"

    echo "setup namespaces"
    add_netns ns0 $IP1
    add_netns ns1 $IP2

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs ns0_veth
    ovs-vsctl add-port br-ovs ns1_veth

    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs "arp,actions=normal"
    ovs-ofctl add-flow br-ovs "table=0, icmp,ct_state=-trk actions=ct(table=1,zone=1)"
    ovs-ofctl add-flow br-ovs "table=1, icmp,ct_state=+trk+new actions=ct(commit,zone=1),normal"
    ovs-ofctl add-flow br-ovs "table=1, icmp,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color

    echo "run traffic"
    ip netns exec ns0 ping -q -c 10 -i 0.1 -w 2 $IP2 -s 2000

    # current ovs with workaround to pass to tc ct rules with frag flag.
    # so don't check for tc rules and don't check for offload.

    echo ovs-appctl dpctl/dump-flows
    ovs-appctl dpctl/dump-flows | grep --color -E "frag=first|$"
    echo ""

    print_tc=false
    ovs-appctl dpctl/dump-flows | grep -i "frag=first.*bytes:0" -q && err "have frag=first rule with bytes:0" && print_tc=true
    if $print_tc; then
        echo "tc stats"
        tc -s filter show dev ns0_veth ingress proto ip chain 0
    fi

    ovs-vsctl del-br br-ovs
}


run
test_done
