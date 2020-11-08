#!/bin/bash
#
# Test OVS with vlan traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}

require_remote_server

IP=1.1.1.7
REMOTE=1.1.1.8

vlan=5
vlan_dev=${REMOTE_NIC}.$vlan

config_sriov 2
enable_switchdev
require_interfaces REP NIC
unbind_vfs
bind_vfs
reset_tc_cacheable $REP $NIC


function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev $vlan_dev &>/dev/null
}

function cleanup() {
    ip a flush dev $NIC
    ip netns del ns0 &>/dev/null
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config() {
    cleanup
    ip netns add ns0
    ip link set dev $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP/24 up
}

function config_remote() {
    on_remote "\
        ip a flush dev $REMOTE_NIC;\
        ip link add link $REMOTE_NIC name $vlan_dev type vlan id $vlan;\
        ip a add $REMOTE/24 dev $vlan_dev;\
        ip l set dev $vlan_dev up"
}

function e2e_cache_verify() {
    for i in $REP $NIC ; do
        title e2e_cache $i
        tc_filter show dev $i ingress e2e_cache
        tc_filter show dev $i ingress e2e_cache | grep -q vlan
        if [ "$?" != 0 ]; then
            err "Expected e2e_cache vlan rule"
        fi
    done
}

function run() {
    config
    config_remote
    tc_test_verbose
    reset_tc_cacheable $REP $NIC

    echo "add arp rules"
    tc_filter add dev $REP ingress protocol arp prio 1 flower $tc_verbose \
        action vlan push id $vlan \
        action mirred egress redirect dev $NIC

    tc_filter add dev $NIC ingress protocol 802.1Q prio 1 flower $tc_verbose \
        vlan_ethtype arp \
        action vlan pop \
        action mirred egress redirect dev $REP

    echo "add icmp rules"
    tc_filter add dev $REP ingress protocol ip prio 2 flower $tc_verbose \
        ip_proto icmp \
        action vlan push id $vlan \
        action mirred egress redirect dev $NIC

    tc_filter add dev $NIC ingress protocol 802.1Q prio 2 flower $tc_verbose \
        vlan_ethtype ip \
        ip_proto icmp \
        action vlan pop \
        action mirred egress redirect dev $REP

    echo "add ct rules"
    tc_filter add dev $REP ingress protocol ip prio 3 flower $tc_verbose \
        ct_state -trk \
        action ct action goto chain 1

    tc_filter add dev $REP ingress protocol ip chain 1 prio 3 flower $tc_verbose \
        ct_state +trk+new \
        action ct commit \
        action vlan push id $vlan \
        action goto chain 2

    tc_filter add dev $REP ingress protocol ip chain 1 prio 3 flower $tc_verbose \
        ct_state +trk+est \
        action vlan push id $vlan \
        action goto chain 2

    tc_filter add dev $REP ingress protocol all chain 2 prio 3 flower $tc_verbose \
        action mirred egress redirect dev $NIC

    # chain0,ct -> chain1,fwd
    tc_filter add dev $NIC ingress protocol 802.1Q prio 3 flower $tc_verbose \
        action ct action goto chain 1

    tc_filter add dev $NIC ingress protocol 802.1Q prio 3 chain 1 flower $tc_verbose \
        ct_state +trk+est \
        vlan_ethtype ip \
        action vlan pop \
        action mirred egress redirect dev $REP

    echo $NIC
    tc filter show dev $NIC ingress
    echo $REP
    tc filter show dev $REP ingress

    # icmp
    ip netns exec ns0 ping -q -c 1 -w 1 $REMOTE
    if [ $? -ne 0 ]; then
        err "ping failed"
        return
    fi

    t=15
    # traffic
    ssh2 $REMOTE_SERVER timeout $((t+2)) iperf -s -t $t &
    pid1=$!
    sleep 2
    ip netns exec ns0 timeout $((t+2)) iperf -c $REMOTE -t $t &
    pid2=$!

    # verify pid
    sleep 2
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
        err "iperf failed"
        return
    fi

    timeout $((t-2)) tcpdump -qnnei $REP -c 10 'tcp' &
    tpid=$!
    sleep $t
    verify_no_traffic $tpid

    e2e_cache_verify

    kill -9 $pid1 &>/dev/null
    killall iperf &>/dev/null
    echo "wait for bgs"
    wait
}

run
reset_tc $NIC $REP
test_done
