#!/bin/bash
#
# Test act_sample action.
#
# act_sample uses psample kernel module. In order to verify the test result,
# introduce a program 'psample' to verify it.
# 'psample' can print input ifindex, sample rate, trunc size, sequence number
# and the packet content.
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
DSTPORT=4789

psample_dir=$my_dir/psample

require_module act_sample psample

test -x $psample_dir/psample || make -C $psample_dir || \
    fail "failed to compile psample in dir $psample_dir"

LOCAL_MAC=$(cat /sys/class/net/$VF/address)
VXLAN_MAC=24:25:d0:e2:00:00

test "$LOCAL_MAC" || fail "no LOCAL_MAC"

function cleanup() {
    ip netns del ns0 2> /dev/null
    reset_tc $REP
    ip link del dev vxlan1 2> /dev/null
    cleanup_remote
}
trap cleanup EXIT

function run() {
    skip=$2
    title $1
    reset_tc $NIC $REP vxlan1
    local n=10
    local file=/tmp/psample.txt
    local rate=1

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

    echo "add vxlan sample rules"
    tc_filter add dev $REP protocol ip parent ffff: prio 2 flower $skip \
        src_mac $LOCAL_MAC                      \
        dst_mac $VXLAN_MAC                      \
        action sample rate $rate group 5        \
        action tunnel_key set                   \
        src_ip $LOCAL_TUN                       \
        dst_ip $REMOTE_IP                       \
        dst_port $DSTPORT                       \
        id $VXLAN_ID                            \
        action mirred egress redirect dev vxlan1

    tc_filter add dev vxlan1 protocol ip parent ffff: prio 3 flower $skip \
        src_mac $VXLAN_MAC                      \
        dst_mac $LOCAL_MAC                      \
        enc_src_ip $REMOTE_IP                   \
        enc_dst_ip $LOCAL_TUN                   \
        enc_dst_port $DSTPORT                   \
        enc_key_id $VXLAN_ID                    \
        action sample rate $rate group 6        \
        action tunnel_key unset                 \
        action mirred egress redirect dev $REP

    fail_if_err

    tc filter show dev $REP ingress
    tc filter show dev vxlan1 ingress

    pkill psample
    timeout 2 $psample_dir/psample -n $n > $file &
    pid=$!

    title "run traffic"
    ip netns exec ns0 ping -q -c $n -i 0.1 -w 2 $REMOTE || err "Ping failed"

    fail_if_err
    wait $pid

    title "verify sample"

    grep "src ipv4: $REMOTE_IP" $file > /dev/null
    if (( $? == 0 )); then
        success2 "get correct tunnel src IP $REMOTE_IP"
    else
        err "get wrong tunnel src IP"
    fi

    grep "dst ipv4: $LOCAL_TUN" $file > /dev/null
    if (( $? == 0 )); then
        success2 "get correct tunnel dst IP $LOCAL_TUN"
    else
        err "get wrong tunnel dst IP"
    fi

    grep "tunnel id: $VXLAN_ID" $file > /dev/null
    if (( $? == 0 )); then
        success2 "get correct tunnel id $VXLAN_ID"
    else
        err "get wrong tunnel id"
    fi

    grep "dst port: $DSTPORT" $file > /dev/null
    if (( $? == 0 )); then
        success2 "get correct tunnel dst port $DSTPORT"
    else
        err "get wrong tunnel dst port"
    fi
}

function config_vxlan() {
    echo "config vxlan dev"
    ip link add vxlan1 type vxlan dstport $DSTPORT external
    ip link set vxlan1 up
    ifconfig $NIC $LOCAL_TUN/24 up
}

function config_remote() {
    on_remote ip link del vxlan1 &>/dev/null
    on_remote ip link add vxlan1 type vxlan id $VXLAN_ID dev $REMOTE_NIC dstport $DSTPORT
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip a add $REMOTE/24 dev vxlan1
    on_remote ip l set dev vxlan1 up
    on_remote ip l set vxlan1 address $VXLAN_MAC
    on_remote ip l set dev $REMOTE_NIC up
}

function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev vxlan1 &>/dev/null
}

config_sriov 1
enable_switchdev
require_interfaces REP
unbind_vfs
bind_vfs
config_vxlan
config_vf ns0 $VF $REP $IP
reset_tc $NIC $REP vxlan1
config_remote

run "Test act_sample action with skip_hw" skip_hw
run "Test act_sample action" ""

test_done
