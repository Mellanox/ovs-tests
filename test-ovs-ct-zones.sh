#!/bin/bash
#
# Test OVS CT with multiple zones
#
# Bug SW #2955534: Existing connection in conntrack table with OFFLOAD/ASSURED status bit doesn't flush intermittently
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
    conntrack -F &>/dev/null
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    ip -all netns del 2>/dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function configure_rules() {
    local orig_dev=$1
    local reply_dev=$2
    local extra_openflow=$3

    ovs-ofctl del-flows ovs-br
    ovs-ofctl add-flow ovs-br "table=0, arp, actions=normal"

    #ORIG
    ovs-ofctl add-flow ovs-br "table=0, ip,in_port=$orig_dev,ct_state=-trk, actions=ct(zone=5, table=5)"

    ovs-ofctl add-flow ovs-br "table=5, ip,in_port=$orig_dev,ct_state=+trk+new, actions=ct(zone=5, commit),ct(zone=7, table=7)"
    ovs-ofctl add-flow ovs-br "table=5, ip,in_port=$orig_dev,ct_state=+trk+est, actions=ct(zone=7, table=7)"

    ovs-ofctl add-flow ovs-br "table=7, ip,in_port=$orig_dev,ct_state=+trk+new, actions=ct(zone=7, commit),output:$reply_dev"
    ovs-ofctl add-flow ovs-br "table=7, ip,in_port=$orig_dev,ct_state=+trk+est, actions=output:$reply_dev"

    #REPLY
    ovs-ofctl add-flow ovs-br "table=0, ip,in_port=$reply_dev,ct_state=-trk,tcp,$extra_openflow actions=ct(zone=7, table=8)"
    ovs-ofctl add-flow ovs-br "table=8, ip,in_port=$reply_dev,ct_state=+trk+est,tcp actions=ct(zone=5, table=9)"
    ovs-ofctl add-flow ovs-br "table=9, ip,in_port=$reply_dev,ct_state=+trk+est,tcp actions=output:$orig_dev"

    ovs-ofctl dump-flows ovs-br --color
}

function config_veth() {
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

function verify_tuples_are_cleared() {
    local i
    local ok=0

    title "Verify tuples are cleared from offload"
    for i in `seq 6`; do
        cat /proc/net/nf_conntrack | grep "$IP1" | grep "$IP2" | grep "zone=[57]" | grep -i offload && sleep 2 && continue
        echo "tuples cleared after $(((i-1)*2)) seconds"
        ok=1
        break
    done
    [ $ok == 0 ] && err "Connections not closed properly"
}

function run() {
    local ovsdev1=$1
    local ovsdev2=$2
    local ns1dev=$3
    local hw=$4
    local extra_openflow=$5
    local run_title=$6

    title "Test OVS CT with multiple zones - $run_title"

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br ovs-br
    ovs-vsctl add-port ovs-br $ovsdev1
    ovs-vsctl add-port ovs-br $ovsdev2
    configure_rules $ovsdev1 $ovsdev2 "$extra_openflow"

    t=15

    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &

    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 &

    sleep 2
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $ns1dev"
    ip netns exec ns1 timeout $t tcpdump -qnnei $ns1dev -c 10 tcp &
    pid1=$!

    if $hw; then
        echo "sniff packets on $ovsdev1"
        timeout $((t-4)) tcpdump -qnnei $ovsdev1 -c 10 'tcp' &
        pid=$!
    fi

    title "Verfiy ovs rules"
    ovs_dump_tc_flows --names
    ovs_dump_tc_flows --names | grep -q "ct(.*commit.*)" || err "Expected ct commit action"

    sleep 2
    title "Verify tuples are offloaded"
    cat /proc/net/nf_conntrack | grep "$IP1" | grep "$IP2" | grep "zone=[57]" | grep -i offload || err "Connections not offloaded to flow table"

    sleep $((t-2))
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    title "Verify traffic on $ns1dev"
    verify_have_traffic $pid1

    if $hw; then
         title "Verify no traffic on $ovsdev1"
         verify_no_traffic $pid
    fi

    verify_tuples_are_cleared

    ovs-vsctl del-br ovs-br
}

cleanup
config_veth ns0 $IP1
config_veth ns1 $IP2
run ns0_veth ns1_veth ns1_peer false "" "tc only"

cleanup
config_veth ns0 $IP1
config_veth ns1 $IP2
run ns0_veth ns1_veth ns1_peer false "tcp_flags=-fin" "tc only - no reply fin (lookup bug)"

cleanup
config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2
run $REP $REP2 $VF2 true "" "hw"

test_done
