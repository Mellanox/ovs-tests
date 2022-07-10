#!/bin/bash
#
# Test ovs ct restore with tcp traffic
#
# Bug SW #2610580: conntrack table full and kernel leaks with MOFED

my_dir="$(dirname "$0")"
. $my_dir/common.sh
pktgen=$my_dir/scapy-traffic-tester.py

require_module act_ct

ip="7.7.7.1"
ip_remote="7.7.7.2"

config_sriov 2
enable_switchdev
require_interfaces REP
unbind_vfs
bind_vfs
reset_tc $REP

VETH_REP=vrep0
VETH_VF=vvf0

function cleanup() {
    ovs-vsctl del-br br-ovs &>/dev/null

    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    ip link del dev $VETH_REP &>/dev/null
    ip link del dev $VETH_VF &>/dev/null
}
trap cleanup EXIT

function swap_recirc_id() {
    echo $@ | grep -q -P "^recirc_id" && echo $@ && return

    recirc_id=`echo $@ | grep -o -P "recirc_id\(\dx?\d*\)"`
    rest=`echo $@ | sed 's/recirc_id(0x\?{:digit:]]*),//'`

    echo ${recirc_id},${rest}
}

function sorted_dump_flow_swap_recirc_id() {
    ovs-appctl dpctl/dump-flows $@ | while read x; do swap_recirc_id $x; done | sort
}

function ddumpct() {
    ports=`ovs-dpctl show | grep port | cut -d ":" -f 2 | grep -v internal`
    for p in $ports; do
        sorted_dump_flow_swap_recirc_id --names $@ | grep 'eth_type(0x0800)' | grep "in_port($p)"
        echo ""
    done
}

function config() {
    ip link add $VETH_REP type veth peer name $VETH_VF

    mac1=`cat /sys/class/net/$VF/address`
    remote_mac=`cat /sys/class/net/$VETH_VF/address`

    test "$mac1" || fail "no mac1"
    test "$remote_mac" || fail "no remote_mac"

    config_vf ns0 $VF $REP $ip
    config_vf ns1 $VETH_VF $VETH_REP $ip_remote
}

function get_nf_conntrack_counter_diff() {
   conntrack -F &>/dev/null
   echo $(bc <<< `conntrack -C`-`conntrack -L 2>/dev/null | wc -l`)
}
olddiff=`get_nf_conntrack_counter_diff`
tuple=""

function verify_nf_conntrack_counter() {
    local diff=`get_nf_conntrack_counter_diff`
    local newdiff=$((diff-olddiff))

    title "verify nf conntrack counter"
    if [ "$newdiff" != "0" ]; then
        err "Expected conntrack dump to match conntrack table count, diff $newdiff, dumping dying table to see if connection is there"

        title "verify conntrack dying table"
        conntrack -L dying | grep -i "zone=3" | grep -i --color=always "$tuple\|$"
        sleep 2
        conntrack -L dying 2>/dev/null | grep -i "zone=3" | grep -i "$tuple" | err "Tuple is stuck in dying phase"
    fi
}

function run() {
    title "Test OVS CT tcp - miss and continue in software"

    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $VETH_REP

    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs "arp,actions=normal"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,in_port=$REP       actions=ct(zone=3, table=1)"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,in_port=$VETH_REP  actions=ct(zone=3, table=1)"

    ovs-ofctl add-flow br-ovs "table=1, ip,in_port=$REP,ct_state=+trk+new, actions=ct(commit, zone=3),output:$VETH_REP"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est,in_port=$REP,       actions=output:$VETH_REP"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est,in_port=$VETH_REP,  actions=output:$REP"

    ovs-ofctl dump-flows br-ovs --color

    echo "sleep before traffic"
    sleep 2
    t=6
    pkts=200

    title "start tcpdump to sniff syn and ack packets"
    timeout $t tcpdump -qnnei $REP -c 2 'tcp' &
    pid=$!

    title "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+2)) iperf -s -i 1 -p 21845 &
#    ip netns exec ns1 timeout $((t+1)) iperf3 -s -i 1 -D
#    ip netns exec ns1 $pktgen -l -i $VETH_VF --src-ip $ip --time $((t+1)) &
#    ip netns exec ns1 timeout $t ./py-server.py $ip_remote 7000 &
    sleep 1
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $ip_remote -p 21845 &
#    ip netns exec ns0 timeout $((t+1)) iperf3 -u -t $t -c $ip_remote &
#    ip netns exec ns0 $pktgen -i $VF1 --src-ip $ip --dst-ip $ip_remote --time $t &
#    ip netns exec ns0 timeout $t ./py-client.py $ip_remote 7000

    echo "wait for syn/ack tcpdump to capture handshake"
    wait $pid
    rc=$?
    if [[ $rc != 0 ]]; then
        err "fail to capture tcp handshake"
    fi

    pidof iperf &>/dev/null || err "iperf failed"

    echo "sleep to wait for offload"
    sleep 2

    # we cat twice. statiscally we fail first time but always succeed second time.
    cat /proc/net/nf_conntrack >/dev/null
    res=`cat /proc/net/nf_conntrack`
    tuple=`echo "$res" | grep -i "zone=3" | grep -o "src=$ip .*dst=$ip_remote .*src" | cut -d "s" -f 1-4`
    echo "tuple: $tuple"

    title "check if tuple offloaded to hardware"
    echo "$res" | grep "$tuple" | grep -i --color=always 'hw_offload\|$'
    echo "$res" | grep "$tuple" | grep -q -i hw_offload || err "tuple not offloaded to flow table"

    title "ovs dump"
    ddumpct

    title "sniff $pkts software packets on $REP to /tmp/dump"
    rm -f /tmp/dump
    timeout $((t-4)) tcpdump -qnnei $REP -c $pkts 'tcp' -w /tmp/dump &
    pid=$!

    sleep $t
    killall -q -9 iperf
    wait $! 2>/dev/null

    # test sniff or timeout
    wait $pid
    rc=$?
    if [[ $rc -eq 0 ]]; then
        :
    else
        err "Failed to catch $pkts packets in software"
    fi

    echo "wait for dying to be removed from list"

    sleep 1
    ovs-vsctl del-br br-ovs
    verify_nf_conntrack_counter
}

config
run

test_done
