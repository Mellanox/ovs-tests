#!/bin/bash
#
# Test OVS CT ipv6 to remote server
#
# Require external server
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}

require_remote_server

IP="2001:0db8:0:f101::1"
REMOTE="2001:0db8:0:f101::2"

enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs


function set_nf_liberal() {
    nf_liberal="/proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal"
    if [ -e $nf_liberal ]; then
        echo 1 > $nf_liberal
        echo "`basename $nf_liberal` set to: `cat $nf_liberal`"
    else
        echo "Cannot find $nf_liberal"
    fi
}

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    set_nf_liberal
    conntrack -F
    # WA SimX bug? interface not receiving traffic from tap device to down&up to fix it.
    for i in $NIC $VF $REP ; do
            ip link set $i down
            ip link set $i up
            reset_tc $i
    done
    ip addr flush dev $NIC
    ip link set dev $NIC up
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ip a add $IP/64 dev $VF
    ip netns exec ns0 ip link set dev $VF up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs $NIC
}

function config_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE/64 dev $REMOTE_NIC
    on_remote ip l set dev $REMOTE_NIC up
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl add-flow br-ovs icmp6,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, ip6,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, ip6,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip6,ct_state=+trk+est actions=normal"
    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    config
    config_remote
    add_openflow_rules

    # icmp
    sleep 1
    ip netns exec ns0 ping -6 -q -c 1 -i 0.1 -w 2 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    t=15

    # initial traffic
    # this part is important when using multi-table CT.
    # the initial traffic will cause ovs to create initial tc rules
    # and also tuple rules. but since ovs adds the rules somewhat late
    # conntrack will already mark the conn est. and tuple rules will be in hw.
    # so we start second traffic which will be faster added to hw before
    # conntrack and this will check the miss rule in our driver is ok
    # (i.e. restoring reg_0 correctly)
    ssh2 $REMOTE_SERVER timeout 4 iperf -s -t 3 --ipv6_domain &
    pid1=$!
    sleep 1
    ip netns exec ns0 timeout 3 iperf -c $REMOTE -t 2 --ipv6_domain &
    pid2=$!

    sleep 4
    kill -9 $pid1 $pid2 &>/dev/null
    wait $pid1 $pid2 &>/dev/null

    # traffic
    ssh2 $REMOTE_SERVER timeout $((t+2)) iperf -s -t $t --ipv6_domain &
    pid1=$!
    sleep 1
    ip netns exec ns0 timeout $((t+2)) iperf -c $REMOTE -t $t -P3 --ipv6_domain &
    pid2=$!

    # verify pid
    sleep 4
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    # verify traffic
    ip netns exec ns0 timeout $((t-4)) tcpdump -qnnei $VF -c 30 ip6 &
    tpid1=$!
    timeout $((t-4)) tcpdump -qnnei $REP -c 10 ip6 &
    tpid2=$!
    timeout $((t-4)) tcpdump -qnnei $NIC -c 10 ip6 &
    tpid3=$!

    sleep $t
    title "Verify traffic on $VF"
    verify_have_traffic $tpid1
    title "Verify offload on $REP"
    verify_no_traffic $tpid2
    title "Verify offload on $NIC"
    verify_no_traffic $tpid3

    kill -9 $pid1 $pid2 &>/dev/null
    echo "wait for bgs"
    wait &>/dev/null

    start_clean_openvswitch
    cleanup
    trap - EXIT
}

run
test_done
