#!/bin/bash
#
# Test act_police action.
# Bug SW #2707092, metering doesn't work before version xx.31.0354 xx.32.0114

my_dir="$(dirname "$0")"
. $my_dir/common.sh


min_nic_cx6
require_module act_police
require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42
DSTPORT=4789

VXLAN_MAC=24:25:d0:e2:00:00

RATE=100
BURST=65536
TMPFILE=/tmp/meter.log

function cleanup_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip l del dev vxlan1 &>/dev/null"
}

function cleanup() {
    ip netns del ns0 2> /dev/null
    reset_tc $REP
    ip link del dev vxlan1 2> /dev/null
    ifconfig $NIC 0
    cleanup_remote
}
trap cleanup EXIT

function config_vxlan() {
    echo "config vxlan dev"
    ip link add vxlan1 type vxlan dstport $DSTPORT external
    ip link set vxlan1 up
    ifconfig $NIC $LOCAL_TUN/24 up
}

function config_remote() {
    on_remote "ip link del vxlan1 &>/dev/null
               ip link add vxlan1 type vxlan id $VXLAN_ID dev $REMOTE_NIC dstport $DSTPORT
               ip a flush dev $REMOTE_NIC
               ip a add $REMOTE_IP/24 dev $REMOTE_NIC
               ip a add $REMOTE/24 dev vxlan1
               ip l set dev vxlan1 up
               ip l set vxlan1 address $VXLAN_MAC
               ip l set dev $REMOTE_NIC up"
}

function add_arp_rules() {
    echo "add arp rules"
    tc_filter add dev $REP protocol arp parent ffff: prio 1 flower skip_hw    \
        src_mac $LOCAL_MAC      \
        action tunnel_key set   \
        src_ip $LOCAL_TUN       \
        dst_ip $REMOTE_IP       \
        dst_port $DSTPORT       \
        id $VXLAN_ID            \
        action mirred egress redirect dev vxlan1

    tc_filter add dev vxlan1 protocol arp parent ffff: prio 1 flower skip_hw  \
        src_mac $VXLAN_MAC              \
        enc_src_ip $REMOTE_IP           \
        enc_dst_ip $LOCAL_TUN           \
        enc_dst_port $DSTPORT           \
        enc_key_id $VXLAN_ID            \
        action tunnel_key unset pipe    \
        action mirred egress redirect dev $REP
}

function ping_remote() {
    # icmp
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi
}

function run() {
    add_arp_rules

    echo "add vxlan police rules"
    tc_filter add dev $REP protocol ip parent ffff: prio 2 flower \
        src_mac $LOCAL_MAC                      \
        dst_mac $VXLAN_MAC                      \
        action tunnel_key set                   \
        src_ip $LOCAL_TUN                       \
        dst_ip $REMOTE_IP                       \
        dst_port $DSTPORT                       \
        id $VXLAN_ID                            \
        action mirred egress redirect dev vxlan1

    tc_filter add dev vxlan1 protocol ip parent ffff: prio 3 flower \
        src_mac $VXLAN_MAC                      \
        dst_mac $LOCAL_MAC                      \
        enc_src_ip $REMOTE_IP                   \
        enc_dst_ip $LOCAL_TUN                   \
        enc_dst_port $DSTPORT                   \
        enc_key_id $VXLAN_ID                    \
        action tunnel_key unset                 \
        action police rate ${RATE}mbit burst $BURST conform-exceed drop/pipe \
        action mirred egress redirect dev $REP

    fail_if_err
    ping_remote

    t=10
    # traffic
    ip netns exec ns0 timeout -k 1 $((t+5)) iperf3 -s -1 -J > $TMPFILE &
    sleep 2
    on_remote timeout -k 1 $((t+2)) iperf3 -c $IP -t $t -O 1 -u -l 1400 -b 1G -P2 &

    verify
}

function verify() {
    # verify client pid
    sleep 2.5
    pidof iperf3 &>/dev/null || err "iperf3 failed"

    timeout $((t-2)) tcpdump -qnnei $REP -c 10 'udp' &
    local tpid=$!
    sleep $t
    verify_no_traffic $tpid

    killall -9 iperf3 &>/dev/null
    echo "wait for bgs"
    wait

    verify_iperf3_bw $TMPFILE $RATE
}

function run2() {
    add_arp_rules

    echo "add vxlan police rules"
    tc_filter add dev $REP protocol ip parent ffff: prio 2 flower \
        src_mac $LOCAL_MAC                      \
        dst_mac $VXLAN_MAC                      \
        action police rate ${RATE}mbit burst $BURST conform-exceed drop/pipe \
        action tunnel_key set                   \
        src_ip $LOCAL_TUN                       \
        dst_ip $REMOTE_IP                       \
        dst_port $DSTPORT                       \
        id $VXLAN_ID                            \
        action mirred egress redirect dev vxlan1

    tc_filter add dev vxlan1 protocol ip parent ffff: prio 3 flower \
        src_mac $VXLAN_MAC                      \
        dst_mac $LOCAL_MAC                      \
        enc_src_ip $REMOTE_IP                   \
        enc_dst_ip $LOCAL_TUN                   \
        enc_dst_port $DSTPORT                   \
        enc_key_id $VXLAN_ID                    \
        action tunnel_key unset                 \
        action mirred egress redirect dev $REP

    fail_if_err
    ping_remote

    t=10
    # traffic
    on_remote timeout -k 1 $((t+5)) iperf3  -s -1 -J > $TMPFILE &
    sleep 2
    ip netns exec ns0 timeout -k 1 $((t+2)) iperf3 -u -c $REMOTE -t $t -O 1 -l 1400 -b 1G -P2 &

    verify
}

config_sriov
enable_switchdev
require_interfaces REP
bind_vfs

LOCAL_MAC=$(cat /sys/class/net/$VF/address)

config_vxlan
config_vf ns0 $VF $REP $IP
config_remote


title "limit the speed on vxlan"
reset_tc $REP vxlan1
run

title "limit the speed on rep"
reset_tc $REP vxlan1
run2

cleanup

test_done
