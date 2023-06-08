#!/bin/bash
#
# Test OVS CT UDP NEW connection offload with iperf, and then updating the connection to BIDRECTIONAL established
#
# Bug SW #3487987: [ASAP, Trex, OFED 23.04, NGN] actual numbrer of offloaded connections not as expected over trex
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

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
    title "Test OVS CT UDP"
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

    # Start one sided iperf udp
    t=30
    port1=$((RANDOM%20000 + 10000))
    port2=$((RANDOM%20000 + 10000))
    echo "run traffic for $t seconds from first side"
    # First connection with empty TC qdisc will not be offloaded until after at
    # least 1 second has passed due to driver callback only being registered as
    # a result of adding first CT action to hardware. Run a warmup iperf run to
    # ensure the callback is registered.
    ip netns exec ns0 timeout 1 iperf -t 1 -c $IP2 -u -b 10pps
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -u -b 10pps -B ${IP1}:${port1}&

    sleep 5
    pidof iperf &>/dev/null || err "iperf failed"
    ovs_dump_tc_flows --names
    conntrack -L | grep udp | grep "dst=$IP2" | grep "$port1"
    conntrack -L | grep udp | grep "dst=$IP2" | grep "$port1" | grep "\[UNREPLIED\]" | grep -q "\[OFFLOAD\]" || err "Offloaded unreplied UDP connection not found"

    echo "sniff packets on $REP"
    timeout 5 tcpdump -nnvvvi $REP -c 5 'udp'&
    pid1=$!
    wait $pid1 2>/dev/null
    verify_no_traffic $pid1

    # Start reply traffic via another iperf instance and iperf to modify to the used port
    ip netns exec ns1 /opt/mellanox/iproute2/sbin/tc qdisc add dev $VF2 clsact
    ip netns exec ns1 /opt/mellanox/iproute2/sbin/tc filter add dev $VF2 egress \
       proto ip flower skip_hw \
       ip_proto udp \
       action pedit ex munge udp sport set 5001 pipe \
       action csum ip udp
    ip netns exec ns1 timeout 12 iperf -t 10 -c $IP1 -p $port1 -u -b 10pps -B ${IP2}:${port2} &

    sleep 5
    conntrack -L | grep udp | grep "dst=$IP2" | grep "$port1"
    conntrack -L | grep udp | grep "dst=$IP2" | grep "$port1" | grep -v "\[UNREPLIED\]" |  grep -q "\[OFFLOAD\]" || err "Tuple didn't switch to REPLIED"
    timeout 5 tcpdump -nnvvvi $REP2 -c 5 'udp'&
    pid2=$!
    wait $pid2 2>/dev/null
    verify_no_traffic $pid2

    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    ovs-vsctl del-br br-ovs
}


run
test_done
