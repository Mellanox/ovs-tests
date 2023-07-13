#!/bin/bash
#
# Test host direction SF fast path traffic from SF to VF.
# after cleanup test network direction SF fast path traffic from SF to uplink.

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

require_remote_server

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    log "cleanup"
    on_remote "ip addr flush dev $NIC"
    reset_tc $NIC $REP
    reset_sfs_ns
    remove_sfs
    sleep 10 # WA wait for fw assert that was spotted up to 10 seconds after cleanup.
}

trap cleanup EXIT

function config() {
    local count=$1
    local direction=${2:-""}

    title "Config"

    if [ -z $direction ]; then
        create_sfs $count
    elif [ "$direction" == "network" ]; then
        create_network_direction_sfs $count
    elif [ "$direction" == "host" ]; then
        create_host_direction_sfs $count
    elif [ "$direction" == "both" ]; then
        create_network_direction_sfs $count
        create_host_direction_sfs $count
        ((count+=count))
    fi

    set_sf_eswitch
    reload_sfs_into_ns
    set_sf_switchdev
    verify_single_ib_device $((count*2))
}

function test_ping_sf_host() {
    title "Verify ping SF$id $sf<->$VF"

    ip netns exec ns0 ifconfig $sf $ip1/24 up
    ip link set dev $sf_rep up
    ip netns exec ns1 ifconfig $VF $ip2/24 up

    reset_tc $REP $sf_rep
    tc_filter add dev $REP ingress protocol arp flower action mirred egress redirect dev $sf_rep
    tc_filter add dev $REP ingress protocol ip flower action mirred egress redirect dev $sf_rep
    tc_filter add dev $sf_rep ingress protocol arp flower action mirred egress redirect dev $REP
    tc_filter add dev $sf_rep ingress protocol ip flower action mirred egress redirect dev $REP

    ip netns exec ns0 ping -w 2 -c 1 $ip2 && success || err "Ping failed for SF$id $sf<->$REP"
    ip netns exec ns1 ip addr flush dev $VF
    reset_tc $REP $sf_rep
}

function test_ping_sf_network() {
    title "Verify ping SF$id $sf<->uplink"

    ip netns exec ns0 ifconfig $sf $ip1/24 up
    ip link set dev $sf_rep up
    on_remote "ip addr flush dev $NIC
               ip addr add $ip2/24 dev $NIC
               ip link set dev $NIC up"

    reset_tc $NIC $sf_rep
    tc_filter add dev $NIC ingress protocol arp flower action mirred egress redirect dev $sf_rep
    tc_filter add dev $NIC ingress protocol ip flower action mirred egress redirect dev $sf_rep
    tc_filter add dev $sf_rep ingress protocol arp flower action mirred egress redirect dev $NIC
    tc_filter add dev $sf_rep ingress protocol ip flower action mirred egress redirect dev $NIC

    ip netns exec ns0 ping -w 2 -c 1 $ip2 && success || err "Ping failed for SF$id $sf<->uplink"
    reset_tc $NIC $sf_rep
}

function test_ping_single() {
    local id=$1
    local dir=$2
    local a sf sf_rep ip1 ip2
    local num=$((-1+$id))

    sf="eth$num"

    local reps=`sf_get_all_reps`
    sf_rep=$(echo $reps | cut -d" " -f$id)

    ip1="$id.$id.$id.1"
    ip2="$id.$id.$id.2"

    if [ $dir == "network" ]; then
        test_ping_sf_network
    else
        test_ping_sf_host
    fi
}

function test_ping() {
    local count=$1
    local dir=$2
    local i

    for i in `seq $count`; do
        test_ping_single $i $dir
    done
}

enable_legacy
config_sriov 2
enable_switchdev
bind_vfs
test_count=2

cleanup
config $test_count "host"
config_vf ns1 $VF $REP
test_ping $test_count "host"

cleanup
config $test_count "network"
test_ping $test_count "network"

trap - EXIT
cleanup
test_done
