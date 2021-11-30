#!/bin/bash
#
# Test OVS CT vxlan traffic with VF mirror
#
# Bug SW #1806549: traffic not offloaded + syndrome (0xd29096) during CT vxlan and mirroring
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_nic cx5 cx6 cx6lx
require_module act_ct
require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

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
    for i in $NIC $VF $REP $VF2 $REP2 ; do
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
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789

    ovs-vsctl add-port br-ovs $REP2
    ovs-vsctl -- --id=@p1 get port $REP2 -- \
                --id=@m create mirror name=m1 select-all=true output-port=@p1 -- \
                set bridge br-ovs mirrors=@m || err "Failed to set mirror port"
    #ovs-vsctl list Bridge br-ovs | grep mirrors
    #ovs-vsctl clear bridge br-ovs mirrors
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

function run() {
    config
    config_remote_vxlan
    add_openflow_rules
    sleep 2

    # icmp
    ip netns exec ns0 ping -q -c 1 -w 2 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    title "Start traffic"
    t=15
    ip netns exec ns0 iperf3 -s -D
    on_remote timeout -k1 $((t+2)) iperf3 -c $IP -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 4
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    ip netns exec ns0 timeout $((t-4)) tcpdump -qnnei $VF -c 30 ip &
    tpid1=$!
    timeout $((t-2)) tcpdump -qnnei $REP -c 10 'tcp' &
    tpid2=$!

    sleep $t
    title "Verify traffic on $VF"
    verify_have_traffic $tpid1
    title "Verify offload on $REP"
    verify_no_traffic $tpid2

    kill -9 $pid1 &>/dev/null
    killall -9 iperf3 &>/dev/null
    echo "wait for bgs"
    wait 2>/dev/null
}

run
ovs-vsctl del-br br-ovs
trap - EXIT
cleanup
test_done
