#!/bin/bash
#
# Test OVS inserting geneve rule with IPv6 addresses
# - create geneve interface in namespace
# - add geneve interface to OVS
# - ping between two interfaces
# - validate that OVS has offloaded the flows (check existing rules)
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"

local_tun="2001:0db8:0:f101::1"
remote_tun="2001:0db8:0:f101::2"


function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip l del dev genev_sys_6081 &>/dev/null
    ip netns del ns0 &> /dev/null

    for i in `seq 0 7`; do
        ip link del veth$i &> /dev/null
    done
}

function check_offloaded_rules() {
    local count=$1
    title " - check for $count offloaded rules"
    if [ "$USE_DPCTL" = 1 ]; then
        RES="ovs_dpctl_dump_flows | grep 0x0800 | grep -v drop"
    else
        RES="ovs_appctl_dpctl_dump_flows | grep 0x0800 | grep -v drop"
    fi
    eval $RES
    RES=`eval $RES | wc -l`
    if (( RES == $count )); then
        success
    else
        ovs-dpctl dump-flows | grep 0x0800
        err
    fi
}

function configure_geneve() {
    local geneve_port=$1

    title "Test geneve with port $geneve_port"
    cleanup

    echo "setup veth and ns"
    ip link add veth0 type veth peer name veth1 || fail "Failed to configure veth"
    ip link add veth2 type veth peer name veth3

    ifconfig veth0 $VM1_IP/24 up
    ifconfig veth1 up

    ip a add dev veth2 $local_tun/64
    ip link set dev veth2 up

    echo "setup ovs dst_port:$geneve_port"
    ovs-vsctl add-br brv-1
    ovs-vsctl add-port brv-1 veth1
    ovs-vsctl add-port brv-1 geneve_ovs -- set interface geneve_ovs type=geneve options:local_ip=$local_tun options:remote_ip=$remote_tun options:key=42 options:dst_port=$geneve_port

    ip netns add ns0
    ip link set veth3 netns ns0
    ip netns exec ns0 ip a add dev veth3 $remote_tun/64
    ip netns exec ns0 ip link set dev veth3 up

    ip netns exec ns0 ip link add dev geneve42 type geneve vni 42 remote $local_tun dstport $geneve_port udp6zerocsumrx
    ip netns exec ns0 ifconfig geneve42 $VM2_IP/24 up

    sleep 1

    title "Test ping $VM1_IP -> $VM2_IP"
    ping -q -c 10 -i 0.2 -w 4 $VM2_IP && success || err

    check_offloaded_rules 2
    cleanup
}

configure_geneve 6081

test_done
