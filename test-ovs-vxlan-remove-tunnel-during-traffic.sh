#!/bin/bash
#
# Test ovs with vxlan
# Remove vxlan tunnel interface during traffic on the receive side.
# Related upstream commit:
# 8e1da73acded gro_cell: add napi_disable in gro_cells_destroy
#
# Bug SW #1609215: [JD] kernel crash removing vxlan tunnel interface during traffic
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


VM1_IP="7.7.7.1"
VM2_IP="7.7.7.2"

local_tun="2.2.2.2"
remote_tun="2.2.2.3"
vxlan_port=4789


function cleanup() {
    stop_traffic &>/dev/null
    ip l del dev vxlan_sys_4789 &>/dev/null
    ip netns del ns0 &> /dev/null
    for i in `seq 0 7`; do
        ip link del veth$i &> /dev/null
    done
}

function config_vxlan() {
    ip netns exec ns0 ip link add name vxlan42 type vxlan id 42 dev veth3 remote $local_tun dstport $vxlan_port
    ip netns exec ns0 ifconfig vxlan42 $VM2_IP/24 up
}

function config_ns() {
    echo "setup veth and ns"
    ip link add veth0 type veth peer name veth1 || fail "Failed to configure veth"
    ip link add veth2 type veth peer name veth3

    ifconfig veth0 $VM1_IP/24 up
    ifconfig veth1 up
    ifconfig veth2 $local_tun/24 up

    ip netns add ns0
    ip link set veth3 netns ns0
    ip netns exec ns0 ifconfig veth3 $remote_tun/24 up
}

function config_ovs() {
    echo "setup ovs dst_port:$vxlan_port"
    start_clean_openvswitch
    ovs-vsctl add-br brv-1
    ovs-vsctl add-port brv-1 veth1
    ovs-vsctl add-port brv-1 vxlan0 -- set interface vxlan0 type=vxlan options:local_ip=$local_tun options:remote_ip=$remote_tun options:key=42 options:dst_port=$vxlan_port
}

function get_vxlan_rx_pkt_count() {
    ip netns exec ns0 ip -s link show dev vxlan42 | grep RX: -A1 | tail -1 | awk {'print $2'}
}

function stop_traffic() {
    echo "stop traffic"
    killall -9 iperf &>/dev/null
    killall -9 noodle &>/dev/null
    wait &>/dev/null
}

function start_traffic() {
    # expecting issue to reproduce when we have at least ~90kpps
    echo "start traffic $VM1_IP -> $VM2_IP"
    timeout $((runtime+5)) iperf -u -c $VM2_IP -b 1G -P 8 -t $runtime &

    # noodle commands that also help reproduce the issue
    # $my_dir/noodle -c $VM2_IP -b 150 -p 9999 -C 10000 -n 5000 &
    # $my_dir/noodle -c $VM2_IP -b 50 -p 9999 -C 5000 -n 5000 &
}

function start_test() {
    title "Test destroy vxlan interface during traffic"

    config_ns
    config_vxlan
    config_ovs

    runtime=60
    start_traffic
    sleep 2
    for i in `seq $((runtime-5))` ; do
        stats=`get_vxlan_rx_pkt_count`
        echo "stats $stats"
        if [ "$stats" == "0" ]; then
            err "Zero stats on vxlan interface"
            break
        fi
        ip netns exec ns0 ip link del dev vxlan42 || err "Failed to remove tunnel interface"
        config_vxlan
        sleep 1
    done

    stop_traffic
    cleanup
}

trap cleanup EXIT
cleanup
start_test

test_done
