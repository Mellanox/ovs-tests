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

require_remote_server
require_module act_sample psample
compile_psample

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42
DSTPORT=4789


function cleanup() {
    ip netns del ns0 2> /dev/null
    reset_tc $REP
    ip link del dev vxlan1 2> /dev/null
    cleanup_remote_vxlan
}
trap cleanup EXIT

function run() {
    local skip=$2
    title $1
    reset_tc $NIC $REP vxlan1
    local n=10
    local file=/tmp/psample.txt
    local rate=1

    echo "add arp rules"
    tc_filter add dev $REP protocol arp parent ffff: prio 1 flower skip_hw    \
        action tunnel_key set   \
        src_ip $LOCAL_TUN       \
        dst_ip $REMOTE_IP       \
        dst_port $DSTPORT       \
        id $VXLAN_ID            \
        action mirred egress redirect dev vxlan1
    tc_filter add dev vxlan1 protocol arp parent ffff: prio 1 flower skip_hw  \
        enc_src_ip $REMOTE_IP           \
        enc_dst_ip $LOCAL_TUN           \
        enc_dst_port $DSTPORT           \
        enc_key_id $VXLAN_ID            \
        action tunnel_key unset pipe    \
        action mirred egress redirect dev $REP

    echo "add vxlan sample rules"
    tc_filter add dev $REP protocol ip parent ffff: prio 2 flower $skip \
        action sample rate $rate group 5        \
        action tunnel_key set                   \
        src_ip $LOCAL_TUN                       \
        dst_ip $REMOTE_IP                       \
        dst_port $DSTPORT                       \
        id $VXLAN_ID                            \
        action mirred egress redirect dev vxlan1

    echo $REP
    tc filter show dev $REP ingress
    [ -z "$skip" ] && verify_in_hw $REP 2

    tc_filter add dev vxlan1 protocol ip parent ffff: prio 3 flower $skip \
        enc_src_ip $REMOTE_IP                   \
        enc_dst_ip $LOCAL_TUN                   \
        enc_dst_port $DSTPORT                   \
        enc_key_id $VXLAN_ID                    \
        action sample rate $rate group 6        \
        action tunnel_key unset                 \
        action mirred egress redirect dev $REP

    echo vxlan1
    tc filter show dev vxlan1 ingress
    [ -z "$skip" ] && verify_in_hw vxlan1 3

    fail_if_err

    pkill psample
    timeout -k 1 2 $psample_dir/psample -n $n > $file &
    pid=$!

    title "run traffic"
    ip netns exec ns0 ping -q -c $n -i 0.1 -w 2 $REMOTE || err "Ping failed"

    wait $pid
    fail_if_err

    title "verify sample"

    grep "src ipv4: $REMOTE_IP" $file > /dev/null
    if (( $? == 0 )); then
        success2 "Correct tunnel src IP $REMOTE_IP"
    else
        err "Wrong tunnel src IP"
    fi

    grep "dst ipv4: $LOCAL_TUN" $file > /dev/null
    if (( $? == 0 )); then
        success2 "Correct tunnel dst IP $LOCAL_TUN"
    else
        err "Wrong tunnel dst IP"
    fi

    grep "tunnel id: $VXLAN_ID" $file > /dev/null
    if (( $? == 0 )); then
        success2 "Correct tunnel id $VXLAN_ID"
    else
        err "Wrong tunnel id"
    fi

    grep "dst port: $DSTPORT" $file > /dev/null
    if (( $? == 0 )); then
        success2 "Correct tunnel dst port $DSTPORT"
    else
        err "Wrong tunnel dst port"
    fi
}

function config_vxlan() {
    echo "config vxlan dev"
    ip link add vxlan1 type vxlan dstport $DSTPORT external
    ip link set vxlan1 up
    ifconfig $NIC $LOCAL_TUN/24 up
}


config_sriov 1
enable_switchdev
unbind_vfs
bind_vfs
require_interfaces REP VF NIC
config_vxlan
config_vf ns0 $VF $REP $IP
reset_tc $NIC $REP vxlan1
config_remote_vxlan

run "Test act_sample action with skip_hw" skip_hw
run "Test act_sample action" ""

test_done
