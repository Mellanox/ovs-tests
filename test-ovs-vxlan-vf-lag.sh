#!/bin/bash
#
# Test OVS with vxlan traffic and VF LAG
#
# Bug SW #2062685: [ASAP, OFED 5.0, centos 7.2(default kernel), fw_steering] vxlan traffic over lag is not offloaded
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding
require_remote_server

if [ -z "$REMOTE_NIC2" ]; then
    fail "Remote nic2 is not configured"
fi

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42


function config_ports() {
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    require_interfaces REP NIC
    unbind_vfs
    config_bonding $NIC $NIC2
    fail_if_err
    bind_vfs
}

function cleanup_remote() {
    clear_remote_bonding
    on_remote "ip a flush dev $REMOTE_NIC ; ip a flush dev $REMOTE_NIC2 ; ip l del dev vxlan1" &>/dev/null
}

function cleanup() {
    cleanup_remote
    ip netns del ns0 &>/dev/null
    ip netns del ns1 &>/dev/null
    sleep 0.5
    unbind_vfs
    sleep 1
    clear_bonding
    config_sriov 0 $NIC2
    ip a flush dev $NIC
}
trap cleanup EXIT

function config() {
    cleanup
    config_ports
    ifconfig bond0 $LOCAL_TUN/24 up
    # WA SimX bug? interface not receiving traffic from tap device to down&up to fix it.
    for i in bond0 $NIC $VF $REP ; do
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
}

function config_remote() {
    remote_disable_sriov
    config_remote_bonding
    on_remote "ip link del vxlan1 &>/dev/null
               ip link add vxlan1 type vxlan id $VXLAN_ID dev bond0 dstport 4789
               ip a add $REMOTE_IP/24 dev bond0
               ip a add $REMOTE/24 dev vxlan1
               ip l set dev vxlan1 up
               ip l set dev bond0 up"
}

function run_server() {
    on_remote timeout -k 1 $((t+3)) iperf -s &
    pk1=$!
    sleep 2
}

function run_client() {
    ip netns exec ns0 timeout -k 1 $((t+2)) iperf -c $REMOTE -t $t -P3 &
    pk2=$!
}

function kill_traffic() {
    kill -9 $pk1 &>/dev/null
    kill -9 $pk2 &>/dev/null
    wait $pk1 $pk2 2>/dev/null
}

function run() {
    config
    config_remote

    if [ "$B2B" == 1 ]; then
        # set local and remote to the same port
        echo $active_slave > /sys/class/net/bond0/bonding/active_slave
        on_remote "echo $remote_active > /sys/class/net/bond0/bonding/active_slave"
    fi
    sleep 1

    # icmp
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    t=15
    # traffic
    run_server
    run_client

    # verify pid
    sleep 2
    kill -0 $pk1 &>/dev/null
    p1=$?
    kill -0 $pk2 &>/dev/null
    p2=$?
    if [ $p1 -ne 0 ] || [ $p2 -ne 0 ]; then
        err "traffic failed"
        return
    fi

    timeout $((t-4)) tcpdump -qnnei $REP -c 10 'tcp' &
    tpid=$!

    sleep $t
    title "Verify traffic is offloaded"
    verify_no_traffic $tpid

    kill_traffic
    echo "wait for bgs"
    wait

    iterate_bond_slaves
}

function iterate_bond_slaves() {
    title "Iterate bond slaves"
    for i in `seq 5`; do
        title "Iter $i"
        change_slaves
        count1=`get_rx_pkts $slave1`
        t=10
        run_server
        run_client
        sleep 2
        echo "wait"
        sleep $t
        kill_traffic
        wait
        count2=`get_rx_pkts $slave1`
        ((count1+=100))
        if [ "$count2" -lt "$count1" ]; then
            err "No traffic?"
        fi
    done
}

slave1=$NIC
slave2=$NIC2
active_slave=$NIC
remote_active=$REMOTE_NIC
function change_slaves() {
    title "change active slave from $slave1 to $slave2"
    local tmpslave=$slave1
    slave1=$slave2
    slave2=$tmpslave
    ifconfig $tmpslave down

    if [ "$B2B" == 1 ]; then
        if [ "$remote_active" == $REMOTE_NIC ]; then
            remote_active=$REMOTE_NIC2
        else
            remote_active=$REMOTE_NIC
        fi
        on_remote "echo $remote_active > /sys/class/net/bond0/bonding/active_slave"
    fi

    sleep 2
    ifconfig $tmpslave up
}

start_check_syndrome
run
start_clean_openvswitch
cleanup
check_syndrome
trap - EXIT
test_done
