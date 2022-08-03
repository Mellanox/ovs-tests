#!/bin/bash
#
# Test metering with openvswitch
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

min_nic_cx6
require_module act_police

IP1="7.7.7.1"
IP2="7.7.7.2"

BR=br-ovs
RATE=200
TMPFILE=/tmp/iperf.log

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
}

function config_ovs() {
    ovs-vsctl add-br $BR
    ovs-vsctl add-port $BR $REP
    ovs-vsctl add-port $BR $REP2

    ovs-ofctl del-flows $BR
    ovs-ofctl -O OpenFlow13 add-flow $BR "arp,actions=normal"
    ovs-ofctl -O OpenFlow13 add-flow $BR "icmp,actions=normal"
    ovs-ofctl -O OpenFlow13 add-meter $BR meter=1,kbps,burst,band=type=drop,rate=$((RATE*1000)),burst_size=64
    ovs-ofctl -O OpenFlow13 add-flow $BR "ip,nw_src=${IP2},actions=meter:1,output:${REP}"
    ovs-ofctl -O OpenFlow13 add-flow $BR "ip,nw_src=${IP1},actions=output:${REP2}"

    ovs-ofctl dump-flows $BR -O OpenFlow13 --color
}

function test_udp() {
    title "Test ping"
    ip netns exec ns1 ping -q -c 1 -w 1 $IP1 || err "Ping failed"

    title "Test iperf udp $VF($IP1) -> $VF2($IP2)"
    t=10
    ip netns exec ns0 timeout -k 1 $((t+5)) iperf -f Bytes -s -u > $TMPFILE &
    sleep 2
    ip netns exec ns1 timeout -k 1 $((t+2)) iperf -u -c $IP1 -t $t -u -l 1400 -b2G -P4 &
    pid1=$!

    sleep 2
    kill -0 $pid1 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    timeout $((t-2)) tcpdump -qnnei $REP -c 10 'udp' &
    local tpid=$!

    sleep $t
    verify_no_traffic $tpid

    killall -9 iperf &>/dev/null
    echo "wait for bgs"
    wait &>/dev/null

    local rate=$(cat $TMPFILE | grep "SUM" | grep "Bytes/sec" | awk '{print $6}' | head -1)
    if [ -z "$rate" ]; then
        err "Cannot find rate"
        return
    fi
    rate=`bc <<< 8*$rate/1000/1000`

    verify_rate $rate $RATE
}

enable_switchdev
bind_vfs
cleanup

require_interfaces VF VF2 REP REP2
config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2

start_clean_openvswitch
config_ovs
test_udp

ovs_clear_bridges
cleanup
test_done
