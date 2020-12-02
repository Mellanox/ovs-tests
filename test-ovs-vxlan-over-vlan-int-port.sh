#!/bin/bash
#
# Test OVS with vxlan traffic over vlan and ovs internal port
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
VXLAN_ID=42
vlan=20
vlandev=${REMOTE_NIC}.$vlan

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs


function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev vxlan1 &>/dev/null
    on_remote ip l del dev $vlandev &>/dev/null
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
    # WA SimX bug? interface not receiving traffic from tap device to down&up to fix it.
    for i in $NIC $VF $REP ; do
            ifconfig $i down
            ifconfig $i up
            reset_tc $i
    done

    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP/24 up

    config_ovs
}

function config_ovs() {
    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-phy
    ovs-vsctl add-port br-phy $NIC
    ovs-vsctl add-port br-phy p0 tag=$vlan -- set interface p0 type=internal
    ovs-vsctl add-br br-int
    ovs-vsctl add-port br-int $REP
    ovs-vsctl add-port br-int vxlan0 -- set interface vxlan0 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789

    # Setting the internal port as the tunnel underlay interface #
    ifconfig p0 $LOCAL_TUN/24 up
    ifconfig br-phy up
}

function config_remote() {
    on_remote ip link add link $REMOTE_NIC name $vlandev type vlan id 20
    on_remote ip link del vxlan1 &>/dev/null
    on_remote ip link add vxlan1 type vxlan id $VXLAN_ID dev $vlandev dstport 4789
    on_remote ip a flush dev $vlandev
    on_remote ip a add $REMOTE_IP/24 dev $vlandev
    on_remote ip a add $REMOTE/24 dev vxlan1
    on_remote ip l set dev vxlan1 up
    on_remote ip l set dev $REMOTE_NIC up
    on_remote ip l set dev $vlandev up
}

function run() {
    config
    config_remote

    title "test ping"
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    title "test traffic"
    t=15
    on_remote timeout $((t+2)) iperf -s -t $t &
    pid1=$!
    sleep 1
    ip netns exec ns0 timeout $((t+2)) iperf -c $REMOTE -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 4
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    timeout 4 ip netns exec ns0 tcpdump -qnnei $VF -c 60 'tcp' &
    tpid1=$!
    timeout 4 tcpdump -qnnei $REP -c 10 'tcp' &
    tpid2=$!

    sleep $t
    title "Verify traffic on $VF"
    verify_have_traffic $tpid1
    title "Verify offload on $REP"
    verify_no_traffic $tpid2

    kill -9 $pid1 &>/dev/null
    killall iperf &>/dev/null
    echo "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
