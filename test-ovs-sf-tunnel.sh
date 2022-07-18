#!/bin/bash
#
# Test offloading on vxlan setup with SF as tunnel endpoint
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

min_nic_cx6
require_remote_server

LOCAL_IP="7.7.7.5"
REMOTE_IP="7.7.7.1"
LOCAL_IPV6="2001:0db8:0:f101::1"
REMOTE_IPV6="2001:0db8:0:f101::2"
VF_IP="5.5.5.5"
REMOTE_VF_IP="5.5.5.1"

function cleanup() {
    clean_config
    remove_sfs
}
trap cleanup EXIT

function clean_config() {
    ip addr flush dev $SF &>/dev/null
    ip netns del ns0 &>/dev/null
    start_clean_openvswitch
    cleanup_remote_vxlan
}

function config() {
    local local_ip=$1
    local remote_ip=$2
    local subnet=$3

    title "Config local host"

    ip a add dev $SF $local_ip/$subnet
    ip link set dev $SF up
    ip link set dev $SF_REP up
    config_vf ns0 $VF2 $REP2 $VF_IP
    ip addr flush dev $NIC
    ip link set dev $NIC up

    start_clean_openvswitch
    ovs-vsctl add-br ovs-br
    ovs-vsctl add-port ovs-br $NIC
    ovs-vsctl add-port ovs-br $SF_REP
    ovs-vsctl add-br ovs-br2
    ovs-vsctl add-port ovs-br2 $REP2
    ovs-vsctl add-port ovs-br2 vxlan1 \
        -- set interface vxlan1 type=vxlan \
            options:remote_ip=$remote_ip \
            options:local_ip=$local_ip \
            options:key=98 options:dst_port=4789

    title "Config remote host"
    on_remote "ip link add vxlan1 type vxlan id 98 dev $REMOTE_NIC local $remote_ip dstport 4789 udp6zerocsumrx
               ifconfig vxlan1 $REMOTE_VF_IP/24 up
               ip link set vxlan1 addr 0a:40:bd:30:89:99
               ip addr add $remote_ip/$subnet dev $REMOTE_NIC
               ip link set $REMOTE_NIC up"

    sleep 2
}

function run() {
    local filter="$1"
    local t=5

    # initial traffic to offload
    ip netns exec ns0 ping -I $VF2 $REMOTE_VF_IP -c 1 -w 1 -q || err "Initial ping failed"

    echo "sniff packets on $SF"
    timeout $t tcpdump -qnnei $SF -c 4 "$filter" &
    tpid=$!
    sleep 0.5

    echo "run ping for $t seconds"
    ip netns exec ns0 ping -I $VF2 $REMOTE_VF_IP -c $t -w $((t+2)) -q &
    ppid=$!
    sleep 0.5

    echo "sniff packets on $REP2"
    timeout $t tcpdump -qnnei $REP2 -c 3 -Q in icmp &
    tpid2=$!

    wait $ppid &>/dev/null
    [ $? -ne 0 ] && err "Ping failed" && return 1

    title "test traffic on $SF"
    verify_no_traffic $tpid
    title "test traffic on $REP2"
    verify_no_traffic $tpid2
}

config_sriov 2
enable_switchdev
require_interfaces REP REP2 NIC
unbind_vfs
bind_vfs
remote_disable_sriov

create_sfs 1
fail_if_err "Failed to create sfs"
SF=`sf_get_netdev 1`
SF_REP=`sf_get_rep 1`
echo "SF $SF REP $SF_REP"

title "Test IPv4 tunnel"
clean_config
config $LOCAL_IP $REMOTE_IP 24
# VXLAN IPv4 encap with payload ethertype=IPv4
run "port 4789 and udp[8:2] = 0x0800 & 0x0800 and udp[11:4] = 98 & 0x00FFFFFF and udp[28:2] = 0x0800"

title "Test IPv6 tunnel"
clean_config
config $LOCAL_IPV6 $REMOTE_IPV6 64
# VXLAN IPv6 encap with payload ethertype=IPv4
run "port 4789 and ip6[48:2] = 0x0800 & 0x0800 and ip6[51:4] = 98 & 0x00FFFFFF and ip6[68:2] = 0x0800"

trap - EXIT
cleanup
test_done
