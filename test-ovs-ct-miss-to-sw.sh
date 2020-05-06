#!/bin/bash
#
# Test CT software miss to ovs datapath
#
# We test this by supporting the first recirc action rule which will be tranlsated to goto some chain,
# and its continuation will always be in OVS datapath since it's action (controller) isn't suported.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

ip1="1.1.1.1"
ip2="1.1.1.2"

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
    ovs-vsctl add-port ovs-br $veth
}

function setup() {
    start_clean_openvswitch
    ovs-vsctl set Open_vSwitch . other_config:max-idle=20000
    ovs-vsctl add-br ovs-br

    add_netns ns1 $ip1
    add_netns ns2 $ip2
}

function cleanup() {
    killall -9 nc &> /dev/null
    ip -all netns del
    del_all_bridges
    ovs-vsctl remove Open_vSwitch . other_config max-idle
}
trap cleanup EXIT

function swap_recirc_id() {
    echo `echo $@ | grep -o -P "recirc_id\(\dx?\d*\)"`,`echo $@ | sed 's/recirc_id(0x\?[[:digit:]]*),//'`
}

function sorted_dump_flow_swap_recirc_id() {
    ovs-appctl dpctl/dump-flows $@ | while read x; do swap_recirc_id $x; done | sort
}

function check_ovs_stats() {
    local t=$1
    local exp=$2

    title "Dump flows of type: $t"
    sorted_dump_flow_swap_recirc_id --names "type=$t" | grep 0x0800 | grep "packets:\d*"
    local stats=`sorted_dump_flow_swap_recirc_id --names "type=$t" | grep 0x0800 | grep -o -P "packets:\d+" | cut -d ":" -f 2 | xargs echo`
    if [[ "$stats" != "$exp" ]]; then
        err "Expected ovs dump type=$t stats ($stats) to be $exp"
        return
    fi

    success2 "OVS stats ($stats) for type $t are correct"
}

function check_tc_stats() {
    local dev=${1}_veth
    local exp=$2

    title "Tc filter show on dev $dev"
    tc -s filter show dev $dev ingress proto ip | grep -C 50 "Sent [0-9]* bytes [0-9]* pkt"
    local stats=`tc -s filter show dev $dev ingress proto ip | grep -o "Sent [0-9]* bytes [0-9]* pkt" | cut -d " " -f 4 | xargs echo`
    if [[ "$stats" != "$exp" ]]; then
        err "Expected ovs $1 stats ($stats) to be $exp"
        return
    fi

    success2 "Tc stats ($stats) for dev $dev are correct"
}

function run_scpy_tcp() {
    sport=$((RANDOM%60000 + 1000))
    dport=$((RANDOM%60000 + 1000))

    ip netns exec ns1 ip link set lo up
    ip netns exec ns2 ip link set lo up

    ip netns exec ns1 iptables -A OUTPUT -p tcp --tcp-flags RST RST -j DROP
    ip netns exec ns2 iptables -A OUTPUT -p tcp --tcp-flags RST RST -j DROP

    echo "Connection $ip1:$sport <-> $ip2:$dport - start"

    #----------------- START - handshake --------------

    ip netns exec ns1 python -c "from scapy.all import *; send(IP(src=\"$ip1\",dst=\"$ip2\")/TCP(sport=$sport,dport=$dport,seq=100,flags='S'))"
    ip netns exec ns2 python -c "from scapy.all import *; send(IP(src=\"$ip2\",dst=\"$ip1\")/TCP(sport=$dport,dport=$sport,seq=51,ack=101,flags='SA'))"
    ip netns exec ns1 python -c "from scapy.all import *; send(IP(src=\"$ip1\",dst=\"$ip2\")/TCP(sport=$sport,dport=$dport,seq=101,ack=52,flags='A'))"

    #------------------ DATA --->  --------------------

    ip netns exec ns1 python -c "from scapy.all import *; send(IP(src=\"$ip1\",dst=\"$ip2\")/TCP(sport=$sport,dport=$dport,seq=101,ack=52,flags='A')/\"A1\")"
    ip netns exec ns1 python -c "from scapy.all import *; send(IP(src=\"$ip1\",dst=\"$ip2\")/TCP(sport=$sport,dport=$dport,seq=103,ack=52,flags='A')/\"A2\")"
    ip netns exec ns1 python -c "from scapy.all import *; send(IP(src=\"$ip1\",dst=\"$ip2\")/TCP(sport=$sport,dport=$dport,seq=105,ack=52,flags='A')/\"A3\")"

    #------------------ DATA <---  --------------------

    ip netns exec ns2 python -c "from scapy.all import *; send(IP(src=\"$ip2\",dst=\"$ip1\")/TCP(sport=$dport,dport=$sport,seq=52,ack=107,flags='A')/\"B1\")"
    ip netns exec ns2 python -c "from scapy.all import *; send(IP(src=\"$ip2\",dst=\"$ip1\")/TCP(sport=$dport,dport=$sport,seq=54,ack=107,flags='A')/\"B2\")"

    est=`cat /proc/net/nf_conntrack 2>/dev/null | grep $ip1 | grep $sport | grep $ip2 | grep $dport`

    #------------------ END - teardown  --------------
    ip netns exec ns1 python -c "from scapy.all import *; send(IP(src=\"$ip1\",dst=\"$ip2\")/TCP(sport=$sport,dport=$dport,seq=107,ack=56,flags='FA'))"
    ip netns exec ns2 python -c "from scapy.all import *; send(IP(src=\"$ip2\",dst=\"$ip1\")/TCP(sport=$dport,dport=$sport,seq=56,ack=108,flags='FA'))"
    ip netns exec ns1 python -c "from scapy.all import *; send(IP(src=\"$ip1\",dst=\"$ip2\")/TCP(sport=$sport,dport=$dport,seq=108,ack=57,flags='A'))"

    echo "Connection $ip1:$sport <-> $ip2:$dport - done"
}

function test1() {
    echo "Add open flow rules"
    ovs-ofctl del-flows ovs-br
    ovs-ofctl add-flow ovs-br \
        "table=0, priority=10, arp, action=normal"
    ovs-ofctl add-flow ovs-br \
        "table=0, priority=50, ct_state=-trk, tcp, actions=ct(table=1)"
    ovs-ofctl add-flow ovs-br \
        "table=1, priority=50, ct_state=+trk+new, tcp, actions=ct(commit),normal"
    ovs-ofctl add-flow ovs-br \
        "table=1, priority=50, ct_state=+trk+est, tcp, actions=controller,normal"

    echo "Open flow:"
    ovs-ofctl dump-flows ovs-br

    echo "Flush conntrack:"
    conntrack -F

    echo "Run traffic:"
    est=""
    run_scpy_tcp
    echo "Connection was $est"
    echo $est | grep -vP "ESTABLISHED|OFFLOAD" && err "Connection wasn't established/offloaded"

    check_ovs_stats tc "6 3 0"
    check_ovs_stats ovs "5 3"

    check_tc_stats ns1 "6 6 0 0"
    check_tc_stats ns2 "3 3"
}


cleanup
setup
test1
test_done
