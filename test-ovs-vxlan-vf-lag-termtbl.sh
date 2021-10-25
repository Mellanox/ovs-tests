#!/bin/bash
#
# Test OVS termination table rules with vxlan traffic and VF LAG
#
# [RHEL8.0] Bug SW #2293171: icmpv6 packet from different subnet is not forwarded to vm interface
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module bonding
require_mlxconfig
require_remote_server

if [ -z "$REMOTE_NIC2" ]; then
    fail "Remote nic2 is not configured"
fi

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42
vlan=20
vlandev=${VF}.$vlan

function set_prio_tag_mode() {
    local mode=$1
    fw_config PRIO_TAG_REQUIRED_EN=$mode
}

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
    on_remote "ip a flush dev $REMOTE_NIC
               ip a flush dev $REMOTE_NIC2
               ip l del dev vxlan1" &>/dev/null
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
    set_prio_tag_mode 1 || fail "Cannot set prio tag mode"
    fw_reset
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
    ip netns exec ns0 ifconfig $VF up
    ip netns exec ns0  ip link add link $VF name $vlandev type vlan id $vlan
    ip netns exec ns0 ifconfig $vlandev $IP/24 up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789
    ovs-ofctl add-flow br-ovs "in_port=vxlan1,  action=push_vlan:0x8100,mod_vlan_vid:$vlan,$REP" -O OpenFlow11
    ovs-ofctl add-flow br-ovs "in_port=$REP,  action=pop_vlan,vxlan1"
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
    on_remote timeout $((t+3)) iperf -s &
    pk1=$!
    sleep 2
}

function run_client() {
    ip netns exec ns0 timeout $((t+2)) iperf -c $REMOTE -t $t -P3 &
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

    echo "set active port the port 1"
    echo $NIC > /sys/class/net/bond0/bonding/active_slave
    on_remote "echo $REMOTE_NIC > /sys/class/net/bond0/bonding/active_slave"

    sleep 2

    # icmp
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    echo "set active port the port 2"
    echo $NIC2 > /sys/class/net/bond0/bonding/active_slave
    on_remote "echo $REMOTE_NIC2 > /sys/class/net/bond0/bonding/active_slave"

    sleep 2

    # icmp
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi
}

start_check_syndrome
run
start_clean_openvswitch
cleanup
set_prio_tag_mode 0
fw_reset
config_sriov 2
check_syndrome
trap - EXIT
test_done
