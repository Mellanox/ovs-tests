#!/bin/bash
#
# Test ovs with vxlan rules default and non default ports
#
# Bug SW #1946143: [Upstream] unexpected rules and missing rules after sanity traffic over VXLAN IPv6 with VNI 0
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"

local_tun="2.2.2.2"
remote_tun="2.2.2.3"


function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip l del dev vxlan_sys_4789 &>/dev/null
    ip l del dev vxlan_sys_4000 &>/dev/null
    ip netns del ns0 &> /dev/null

    for i in `seq 0 7`; do
        ip link del veth$i &> /dev/null
    done
}

cleanup

function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    if [ "$USE_DPCTL" = 1 ]; then
        RES="ovs_dpctl_dump_flows | grep 0x0800 | grep -v drop | grep tun_id"
    else
        RES="ovs_dump_tc_flows | grep 0x0800 | grep -v drop | grep tun_id"
    fi
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then
        success
    else
        ovs_dump_flows | grep 0x0800
        err "Found $RES but expected $count"
    fi
}

function configure_vxlan() {
    local vxlan_port=$1
    local vxlan_tun_id=$2

    title "Test vxlan with port $vxlan_port and tun id $vxlan_tun_id"

    echo "setup veth and ns"
    ip link add veth0 type veth peer name veth1 || fail "Failed to configure veth"
    ip link add veth2 type veth peer name veth3

    ifconfig veth0 $VM1_IP/24 up
    ifconfig veth1 up
    ifconfig veth2 up

    ip netns add ns0
    ip link set veth3 netns ns0
    ip netns exec ns0 ifconfig veth3 $remote_tun/24 up

    ip netns exec ns0 ip link add name vxlan42 type vxlan id $vxlan_tun_id dev veth3 remote $local_tun dstport $vxlan_port
    ip netns exec ns0 ifconfig vxlan42 $VM2_IP/24 up

    echo "setup ovs dst_port:$vxlan_port"
    ovs-vsctl add-br brv-1
    ovs-vsctl add-port brv-1 veth1
    ovs-vsctl add-port brv-1 vxlan0 -- set interface vxlan0 type=vxlan options:local_ip=$local_tun options:remote_ip=$remote_tun options:key=$vxlan_tun_id options:dst_port=$vxlan_port

    ifconfig veth2 $local_tun/24 up

    echo "Test ping $VM1_IP -> $VM2_IP"
    ping -q -c 10 -i 0.2 -w 4 $VM2_IP && success || err

    check_offloaded_rules 2
    cleanup
}

configure_vxlan 4789 42
configure_vxlan 4000 42
configure_vxlan 4789 0

test_done
