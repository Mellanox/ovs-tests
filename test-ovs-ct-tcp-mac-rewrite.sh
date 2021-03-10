#!/bin/bash
#
# Test OVS CT TCP traffic with mac rewrite
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
    killall -9 iperf &>/dev/null
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    reset_tc $REP
    reset_tc $REP2
}
trap cleanup EXIT

function run() {
    title "Test OVS CT TCP with mac rewrite"

    real_mac1=`cat /sys/class/net/$VF/address`
    real_mac2=`cat /sys/class/net/$VF2/address`
    fake_mac2="aa:bb:cc:dd:ee:ff"

    config_vf ns0 $VF $REP $IP1
    config_vf ns1 $VF2 $REP2 $IP2

    echo "faking mac from $real_mac2 to $fake_mac2"
    ip netns exec ns0 ip n replace $IP2 dev $VF lladdr $fake_mac2
    ip netns exec ns1 ip n replace $IP1 dev $VF2 lladdr $real_mac1

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $REP2

    ovs-ofctl add-flow br-ovs "table=0, in_port=$REP,dl_dst=$fake_mac2,ip actions=mod_dl_dst=$real_mac2,ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+new actions=ct(commit,table=3)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+est actions=resubmit(,3)"

    ovs-ofctl add-flow br-ovs "table=0, in_port=$REP2,ip actions=mod_dl_src=$fake_mac2,ct(table=2)"
    ovs-ofctl add-flow br-ovs "table=2, ip,ct_state=+trk+new actions=ct(commit,table=3)"
    ovs-ofctl add-flow br-ovs "table=2, ip,ct_state=+trk+est actions=resubmit(,3)"

    ovs-ofctl add-flow br-ovs "table=3, actions=normal"

    ovs-ofctl dump-flows br-ovs --color

    echo "run traffic"
    t=12
    echo "run traffic for $t seconds"
    ip netns exec ns1 timeout $((t+1)) iperf -s &
    sleep 0.5
    ip netns exec ns0 timeout $((t+1)) iperf -t $t -c $IP2 -P 3 -b100Kbps &

    sleep 4
    pidof iperf &>/dev/null || err "iperf failed"

    echo "sniff packets on $REP"
    timeout 4 tcpdump -qnnei $REP -c 10 'tcp' &
    pid=$!

    sleep $t
    killall -9 iperf &>/dev/null
    wait $! 2>/dev/null

    # test sniff timedout
    wait $pid
    rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed"
    fi

    ovs-vsctl del-br br-ovs
}

cleanup
run
test_done
