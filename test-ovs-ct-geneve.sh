#!/bin/bash
#
# Test OVS CT with geneve traffic
#
# Require external server
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct

REMOTE_SERVER=${1:?Require remote server}
REMOTE_NIC=ens1f0

function ssh2() {
    ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o BatchMode=yes $@
}

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
TUN_ID=42

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

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev geneve1 &>/dev/null
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

function on_remote() {
    local cmd=$@
    ssh2 $REMOTE_SERVER $cmd
}

function config_remote() {
    on_remote ip link del geneve1 2>/dev/null
    on_remote ip link add geneve1 type geneve id $TUN_ID remote $LOCAL_TUN dstport 6081
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip a add $REMOTE/24 dev geneve1
    on_remote ip l set dev geneve1 up
    on_remote ip l set dev $REMOTE_NIC up
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs in_port=$REP,dl_type=0x0806,actions=output:geneve1
    ovs-ofctl add-flow br-ovs in_port=geneve1,dl_type=0x0806,actions=output:$REP
    ovs-ofctl add-flow br-ovs in_port=$REP,icmp,actions=output:geneve1
    ovs-ofctl add-flow br-ovs in_port=geneve1,icmp,actions=output:$REP
    ovs-ofctl add-flow br-ovs "table=0, tcp,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, tcp,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, tcp,ct_state=+trk+est actions=normal"
    ovs-ofctl dump-flows br-ovs --color
}

function test_tcpdump() {
    local pid=$1
    wait $pid
    local rc=$?
    if [[ $rc -eq 124 ]]; then
        :
    elif [[ $rc -eq 0 ]]; then
        err "Didn't expect to see packets"
    else
        err "Tcpdump failed"
    fi
}

function run() {
    config
    config_remote
    add_openflow_rules
    #ip a show dev $NIC
    #ip netns exec ns0 ip a s dev $VF

    # icmp
    ip netns exec ns0 ping -q -c 1 -i 0.1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    # tcp
    ssh2 $REMOTE_SERVER timeout 11 iperf -s -t 11 &
    sleep 0.5
    ip netns exec ns0 timeout 11 iperf -c $REMOTE -t 10 -P3 &
    pid1=$!
    sleep 2
    kill -0 $pid1 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
    else
        timeout 8 tcpdump -qnnei $REP -c 10 'tcp' &
        pid2=$!
        sleep 8
        test_tcpdump $pid2
    fi
    wait
}

run
start_clean_openvswitch
test_done
