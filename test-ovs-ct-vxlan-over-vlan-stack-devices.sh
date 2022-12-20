#!/bin/bash
#
# Test OVS with vxlan traffic over vlan and stack devices with
# CT on the internal bridge.
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

min_nic_cx6dx
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
require_interfaces REP NIC REP2
unbind_vfs
bind_vfs


function cleanup_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip l del dev vxlan1 &>/dev/null
               ip l del dev $vlandev &>/dev/null"
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
    for i in $NIC $VF $REP $REP2 $REP2; do
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
    ovs-vsctl add-port br-phy $REP2 tag=$vlan 
    ovs-vsctl add-br br-int
    ovs-vsctl add-port br-int $REP
    ovs-vsctl add-port br-int vxlan0 -- set interface vxlan0 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789

    # Setting the VF2 (stack devices) as the tunnel underlay interface #
    ifconfig $VF2 $LOCAL_TUN/24 up
    ifconfig br-phy up

    ovs-ofctl add-flow br-int "priority=100,in_port=$REP,ip,tcp,actions=ct(table=200,zone=201,nat)"
    ovs-ofctl add-flow br-int "table=200,priority=100,in_port=$REP,ip,tcp,ct_state=+new+trk,actions=ct(commit,zone=201,nat),normal"
    ovs-ofctl add-flow br-int "table=200,priority=100,in_port=$REP,ip,tcp,ct_state=+est+trk,actions=normal"

    ovs-ofctl add-flow br-int "priority=100,in_port=vxlan0,ip,tcp,actions=ct(table=202,zone=201,nat)"
    ovs-ofctl add-flow br-int "table=202,priority=100,in_port=vxlan0,ip,tcp,ct_state=+est+trk,actions=normal"
}

function config_remote() {
    on_remote "ip link add link $REMOTE_NIC name $vlandev type vlan id 20
               ip link del vxlan1 &>/dev/null
               ip link add vxlan1 type vxlan id $VXLAN_ID dev $vlandev dstport 4789
               ip a flush dev $vlandev
               ip a add $REMOTE_IP/24 dev $vlandev
               ip a add $REMOTE/24 dev vxlan1
               ip l set dev vxlan1 up
               ip l set dev $REMOTE_NIC up
               ip l set dev $vlandev up"
}

function run() {
    config
    config_remote

    sleep 2
    title "test ping"
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    title "test traffic"
    t=15
    on_remote timeout $((t+2)) iperf3 -s -D
    sleep 1
    ip netns exec ns0 timeout $((t+2)) iperf3 -c $REMOTE -t $t -P3 &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    timeout $((t-4)) ip netns exec ns0 tcpdump -qnnei $VF -c 60 'tcp' &
    tpid1=$!
    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'tcp' &
    tpid2=$!
    timeout $((t-4)) tcpdump -qnnei $REP2 -c 10 'tcp' &
    tpid3=$!

    sleep $t
    title "Verify traffic on $VF"
    verify_have_traffic $tpid1
    title "Verify offload on $REP"
    verify_no_traffic $tpid2
    title "Verify offload on $REP2"
    verify_no_traffic $tpid3

    kill -9 $pid1 &>/dev/null
    on_remote killall -9 -q iperf3 &>/dev/null
    echo "wait for bgs"
    wait
}

run
start_clean_openvswitch
test_done
