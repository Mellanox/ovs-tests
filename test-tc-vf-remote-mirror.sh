#!/bin/bash
#
# Test VF Mirror basic VF1->remote,remote
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

IP1="7.7.7.1"
IP2="7.7.7.2"
vx=vxlan1
vxlan_port=4789

config_sriov 2
enable_switchdev
unbind_vfs
bind_vfs
require_interfaces REP VF
reset_tc $REP

mac2="e4:11:22:11:77:77"

function cleanup() {
    ip -all netns delete
    ip link del $vx &>/dev/null
    reset_tc $REP
}
trap cleanup EXIT

function run() {
    local ip_src=$1
    local ip_dst=$2

    ip -all netns delete
    title "Test VF Mirror"
    config_vf ns0 $VF $REP $IP1
    echo "ip netns exec ns0 ip neigh add $IP2 lladdr $mac2 dev $VF"
    ip netns exec ns0 ip neigh add $IP2 lladdr $mac2 dev $VF

    title " - create vxlan interface"
    # note: we support adding decap to vxlan interface only.
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dstport $vxlan_port external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set dev $vx up

    ip a show dev $vx

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ip neigh add $ip_dst lladdr e4:11:22:11:55:55 dev $NIC

    TUNNEL_KEY_SET1="action tunnel_key set
        src_ip $ip_src
        dst_ip $ip_dst
        dst_port 4789
        id 768
        ttl 64
        nocsum"
    TUNNEL_KEY_SET2="action tunnel_key set
        src_ip $ip_src
        dst_ip $ip_dst
        dst_port 4789
        id 1024
        ttl 64
        nocsum"

    echo "add vf mirror rules"
    tc_filter add dev $REP ingress protocol ip prio 2 flower skip_sw \
        dst_mac $mac2 \
        $TUNNEL_KEY_SET1 pipe \
        action mirred egress mirror dev $vx pipe \
        $TUNNEL_KEY_SET2 pipe \
        action mirred egress redirect dev $vx

    fail_if_err

    echo $REP
    tc filter show dev $REP ingress

    title "- trigger neigh update event"
    sleep 5
    ip neigh replace $ip_dst dev $NIC lladdr e4:11:22:11:77:88
    sleep 5
    before_count=`get_tx_pkts $NIC`

    packets=20
    interval=0.1
    deadline=5
    echo "run traffic"
    cmd="ip netns exec ns0 ping -q -c $packets -i $interval -w $deadline $IP2"
    echo $cmd
    eval $cmd

    after_count=`get_tx_pkts $NIC`

    diff=$((after_count - before_count))
    echo "transmitted: $diff"

    expected=$((packets*2))
    echo "expected: $expected"

    if [ "$diff" -lt "$expected" ]; then
        err "Expected $expected, transmitted $diff"
    else
        success
    fi
}


run 20.1.11.1 20.1.12.1

test_done
