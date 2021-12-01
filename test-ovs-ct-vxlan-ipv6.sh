#!/bin/bash
#
# Test OVS CT with vxlan traffic over ipv6
#
# #2127467: [ASAP, OFED5.0] no tcp, udp traffic after basic connection tracking rules over vxlan ipv6 tunnel
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-ovs-ct.sh

require_module act_ct
require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN="2001:0db8:0:f101::1"
REMOTE_TUN="2001:0db8:0:f101::2"
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

ovs_ctl="/usr/share/openvswitch/scripts/ovs-ctl"

function cleanup_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ovs-vsctl del-br br-ovs &>/dev/null
               ip link del veth0 &>/dev/null
               $ovs_ctl stop &>/dev/null"
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
    ip netns exec ns0 ifconfig $VF mtu 1200
    ip netns exec ns0 ifconfig $VF $IP/24 up

    echo "Restarting OVS"
    start_clean_openvswitch

    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP
    ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_TUN options:key=$VXLAN_ID options:dst_port=4789
}

function config_remote() {
    # native ipv6 vxlan tunnel doesn't work for me against ovs vxlan ipv6 so using remote ovs
    on_remote "ip a flush dev $REMOTE_NIC
               ip a add $REMOTE_TUN/64 dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up
               $ovs_ctl --delete-bridges start
               ovs-vsctl add-br br-ovs
               ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$REMOTE_TUN options:remote_ip=$LOCAL_TUN options:key=$VXLAN_ID options:dst_port=4789
               ip link add veth0 type veth peer name veth1
               ip link set veth0 up
               ip link set veth1 up
               ovs-vsctl add-port br-ovs veth0
               ip a add $REMOTE/24 dev veth1"
}

function add_openflow_rules() {
    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs icmp,actions=normal
    ovs-ofctl add-flow br-ovs icmp6,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, tcp,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, tcp,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, tcp,ct_state=+trk+est actions=normal"
    ovs-ofctl dump-flows br-ovs --color
}

function run() {
    config
    config_remote
    add_openflow_rules
    sleep 2

    ping_remote
    if [ $? -ne 0 ]; then
        return
    fi

    initial_traffic

    start_traffic
    if [ $? -ne 0 ]; then
        return
    fi

    vxlan_dev="vxlan_sys_4789"
    verify_traffic

    kill_traffic
}

run
ovs-vsctl del-br br-ovs
trap - EXIT
cleanup
test_done
