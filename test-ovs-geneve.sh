#!/bin/bash
#
# Test OVS with geneve traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
TUN_ID=42

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
    on_remote "ip a flush dev $REMOTE_NIC; \
              ip l del dev geneve1 &>/dev/null"
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
    ifconfig $NIC $LOCAL_TUN/24 up
    # WA SimX bug? interface not receiving traffic from tap device to down&up to fix it.
    for i in $NIC $VF $REP ; do
            ifconfig $i down
            ifconfig $i up
            reset_tc $i
    done
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP/24 up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs geneve1 -- set interface geneve1 type=geneve options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$TUN_ID options:dst_port=6081
}

function config_remote() {
    on_remote "ip link del geneve1 &>/dev/null; \
               ip link add geneve1 type geneve id $TUN_ID remote $LOCAL_TUN dstport 6081; \
               ip a flush dev $REMOTE_NIC; \
               ip a add $REMOTE_IP/24 dev $REMOTE_NIC; \
               ip a add $REMOTE/24 dev geneve1; \
               ip l set dev geneve1 up; \
               ip l set dev $REMOTE_NIC up"
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
    ip netns exec ns0 iperf3 -s -D
    on_remote timeout -k1 3 iperf3 -c $IP -t 2
    killall -9 iperf3
}

function run() {
    config
    config_remote
    sleep 1

    # icmp
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    initial_traffic

    # traffic
    ip netns exec ns0 iperf3 -s -D
    on_remote timeout -k1 15 iperf3 -c $IP -t 12 -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        killall -q -9 iperf3
        return
    fi

    # verify traffic
    ip netns exec ns0 timeout 12 tcpdump -qnnei $VF -c 30 ip &
    tpid1=$!
    timeout 12 tcpdump -qnnei $REP -c 10 ip &
    tpid2=$!
    timeout 12 tcpdump -qnnei genev_sys_6081 -c 10 ip &
    tpid3=$!

    sleep 15
    title "Verify traffic on $VF"
    verify_have_traffic $tpid1
    title "Verify offload on $REP"
    verify_no_traffic $tpid2
    title "Verify offload on genev_sys_6081"
    verify_no_traffic $tpid3

    killall -q -9 iperf3
    kill -9 $pid2 &>/dev/null
    echo "wait for bgs"
    wait &>/dev/null
}

run
start_clean_openvswitch
test_done
