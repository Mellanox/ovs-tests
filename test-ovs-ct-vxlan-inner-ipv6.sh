#!/bin/bash
#
# Test OVS CT with vxlan traffic. inner traffic ipv6
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}

require_remote_server

IP="2001:0db8:0:f101::1"
REMOTE="2001:0db8:0:f101::2"

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

# make sure port2 is not configured in switchdev as we could have issue when
# both ports configured. we have test-ovs-ct-vxlan-2.sh and test-ovs-ct-vxlan-3.sh
# to verify with both ports configured.
config_sriov 0 $NIC2
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

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    cleanup_remote_vxlan
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    set_nf_liberal
    conntrack -F
    ifconfig $NIC $LOCAL_TUN/24 up
    # WA SimX bug? interface not receiving traffic from tap device to down&up to fix it.
    for i in $NIC $VF $REP ; do
            ifconfig $i down
            ifconfig $i up
            reset_tc $i
    done
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ip addr add dev $VF $IP/64
    ip netns exec ns0 ip link set dev $VF up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789
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

function initial_traffic() {
    title "initial traffic"
    # this part is important when using multi-table CT.
    # the initial traffic will cause ovs to create initial tc rules
    # and also tuple rules. but since ovs adds the rules somewhat late
    # conntrack will already mark the conn est. and tuple rules will be in hw.
    # so we start second traffic which will be faster added to hw before
    # conntrack and this will check the miss rule in our driver is ok
    # (i.e. restoring reg_0 correctly)
    ip netns exec ns0 iperf -s --ipv6_domain -D
    on_remote timeout -k1 3 iperf --ipv6_domain -c $IP -t 2
    killall -9 iperf
}

function run() {
    config
    config_remote_vxlan
    add_openflow_rules

    # icmp
    sleep 2
    ip netns exec ns0 ping -q -c 1 -w 2 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    initial_traffic

    title "Start traffic"
    t=16
    on_remote timeout $((t+2)) iperf -s --ipv6_domain -t $t &
    pid1=$!
    sleep 2
    ip netns exec ns0 timeout $((t+2)) iperf --ipv6_domain -c $REMOTE -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    # verify traffic
    proto=ip6
    ip netns exec ns0 timeout $((t-4)) tcpdump -qnnei $VF -c 30 $proto &
    tpid1=$!
    timeout $((t-4)) tcpdump -qnnei $REP -c 10 $proto &
    tpid2=$!
    timeout $((t-4)) tcpdump -qnnei vxlan_sys_4789 -c 10 $proto &
    tpid3=$!

    sleep $t
    title "Verify traffic on $VF"
    verify_have_traffic $tpid1
    title "Verify offload on $REP"
    verify_no_traffic $tpid2
    title "Verify offload on vxlan_sys_4789"
    verify_no_traffic $tpid3

    kill -9 $pid1 $pid2 &>/dev/null
    echo "wait for bgs"
    wait &>/dev/null
}

run
ovs-vsctl del-br br-ovs
test_done
