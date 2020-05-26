#!/bin/bash
#
# Test OVS CT with vxlan traffic over ipv6
#
# Bug SW #2127467: [ASAP, OFED5.0-] no tcp, udp traffic after basic connection tracking rules over vxlan ipv6 tunnel
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

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN="2001:0db8:0:f101::1"
REMOTE_TUN="2001:0db8:0:f101::2"
VXLAN_ID=42

enable_switchdev_if_no_rep $REP
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

function remote-ovs-ctl() {
    on_remote /usr/share/openvswitch/scripts/ovs-ctl $@
}

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ovs-vsctl del-br br-ovs &>/dev/null
    remote-ovs-ctl stop
    on_remote ip link del veth0 &>/dev/null
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
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
    ip addr add dev $NIC $LOCAL_TUN/64
    ip link set dev $NIC up
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP/24 up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_TUN options:key=$VXLAN_ID options:dst_port=4789
}

function config_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_TUN/64 dev $REMOTE_NIC
    on_remote ip l set dev $REMOTE_NIC up
    # native ipv6 vxlan tunnel doesn't work for me against ovs vxlan ipv6 so using remote ovs
    remote-ovs-ctl --delete-bridges start
    on_remote ovs-vsctl add-br br-ovs
    on_remote ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$REMOTE_TUN options:remote_ip=$LOCAL_TUN options:key=$VXLAN_ID options:dst_port=4789
    on_remote "ip link add veth0 type veth peer name veth1; \
               ip link set veth0 up; \
               ip link set veth1 up; \
               ovs-vsctl add-port br-ovs veth0; \
               ip a add $REMOTE/24 dev veth1"
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, tcp,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, tcp,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, tcp,ct_state=+trk+est actions=normal"
    ovs-ofctl dump-flows br-ovs --color
}

function test_have_traffic() {
    local pid=$1
    wait $pid
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        :
    elif [[ $rc -eq 124 ]]; then
        err "Expected to see packets"
    else
        err "Tcpdump failed rc $rc"
    fi
}

function test_no_traffic() {
    local pid=$1
    wait $pid
    local rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed rc $rc"
    fi
}

function run() {
    config
    config_remote
    add_openflow_rules

    # icmp
    ip netns exec ns0 ping -q -c 1 -i 0.1 -w 1 $REMOTE
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
    ssh2 $REMOTE_SERVER timeout 4 iperf -s -t 3 &
    pid1=$!
    sleep 1
    ip netns exec ns0 timeout 3 iperf -c $REMOTE -t 2 &
    pid2=$!

    sleep 4
    kill -9 $pid1 $pid2 &>/dev/null
    wait $pid1 $pid2 &>/dev/null

    # traffic
    ssh2 $REMOTE_SERVER timeout $((t+2)) iperf -s -t $t &
    pid1=$!
    sleep 1
    ip netns exec ns0 timeout $((t+2)) iperf -c $REMOTE -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    # verify traffic
    ip netns exec ns0 timeout $((t-2)) tcpdump -qnnei $VF -c 30 ip &
    tpid1=$!
    timeout $((t-2)) tcpdump -qnnei $REP -c 10 ip &
    tpid2=$!
    timeout $((t-2)) tcpdump -qnnei vxlan_sys_4789 -c 10 ip &
    tpid3=$!

    sleep $t
    title "Verify traffic on $VF"
    test_have_traffic $tpid1
    title "Verify offload on $REP"
    test_no_traffic $tpid2
    title "Verify offload on vxlan_sys_4789"
    test_no_traffic $tpid3

    kill -9 $pid1 $pid2 &>/dev/null
    echo "wait for bgs"
    wait &>/dev/null

    start_clean_openvswitch
    cleanup
    trap - EXIT
}

run
test_done
