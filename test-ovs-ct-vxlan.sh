#!/bin/bash
#
# Test OVS CT with vxlan traffic
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

function cleanup() {
    ifconfig $NIC 0
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
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
    #ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
    #ovs-vsctl remove Open_vSwitch . other_config tc-policy
    #systemctl restart openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    #ip netns exec ns0 ip n r 1.1.1.2 dev ens1f2 lladdr 00:00:11:11:11:11
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789
}

function on_remote() {
    local cmd=$@
    ssh2 $REMOTE_NIC $cmd
}

function config_remote() {
    on_remote ip link del vxlan1
    on_remote ip link add vxlan1 type vxlan id $VXLAN_ID dev $REMOTE_NIC dstport 4789
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-ovs
    #ovs-ofctl add-flow br-ovs in_port=$NIC,dl_type=0x0806,actions=output:$REP
    ovs-ofctl add-flow br-ovs in_port=$REP,dl_type=0x0806,actions=output:vxlan1
    ovs-ofctl add-flow br-ovs in_port=vxlan1,dl_type=0x0806,actions=output:$REP
    ovs-ofctl add-flow br-ovs in_port=$REP,icmp,actions=output:vxlan1
    ovs-ofctl add-flow br-ovs in_port=vxlan1,icmp,actions=output:$REP
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
    #config_remote
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

    #ovs-dpctl dump-flows --names
    #/labhome/roid/scripts/ovs-df.sh --names
    #conntrack -L
}

run
start_clean_openvswitch
test_done
