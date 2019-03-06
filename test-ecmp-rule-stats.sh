#!/bin/bash
#
# Testing we return tc rule stats even if when one port is down.
# In vxlan case it also means there is no rule offloaded.
#
# Bug SW #1431290: [IBM ECMP] intermediate high latency pings when a PF is down
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-ecmp.sh

require_mlxdump

local_ip="49.0.10.60"
remote_ip="46.0.10.180"
dst_mac="e4:1d:2d:fd:8b:02"
dst_port=4789
id=98
net=`getnet $remote_ip 24`
[ -z "$net" ] && fail "Missing net"

# default is vxlan
TEST_GRE=0


function cleanup() {
    clean_gre
    cleanup_multipath
}
trap cleanup EXIT

function config_vxlan() {
    echo "config vxlan dev"
    ip link add vxlan1 type vxlan id $id dev $NIC dstport $dst_port
    ip link set vxlan1 up
    ip addr add ${local_ip}/24 dev $NIC
    tc qdisc add dev vxlan1 ingress
}

function config_gre() {
    echo "config gre dev"
    ip link add gre_sys type gretap dev $NIC nocsum
    ip link set gre_sys up
    ip addr add ${local_ip}/24 dev $NIC
    tc qdisc add dev gre_sys ingress
}

function clean_gre() {
    ip l del gre_sys &>/dev/null
}

function add_vxlan_rule() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    tc_filter add dev $REP protocol ip parent ffff: prio 1 \
        flower ip_proto icmp dst_mac $dst_mac skip_sw \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1
}

function add_gre_rule() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    tc_filter add dev $REP protocol ip parent ffff: prio 1 \
        flower ip_proto icmp dst_mac $dst_mac skip_sw \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} nocsum \
        action mirred egress redirect dev gre_sys
}

function config() {
    config_ports
    ifconfig $NIC up
    ifconfig $NIC2 up
    if [ "$TEST_GRE" = 1 ]; then
        config_gre
    else
        config_vxlan
    fi
}

function get_packets() {
    tc -s filter show dev $REP ingress | grep bytes
    a=`tc -j -s filter show dev $REP ingress | jq ".[1].options.actions[1].stats.packets"`
}

function do_traffic() {
    ping -q -I $VF $ping_ip -i 0.1 -c 10 -w 2 &>/dev/null
}

function test_ecmp_rule_stats() {
    config_multipath_route
    is_vf_lag_active || return 1
    bind_vfs $NIC

    title "-- both ports up"
    ifconfig $NIC up
    ifconfig $NIC2 up
    ifconfig $REP up
    ifconfig $VF up
    wait_for_linkup $NIC
    wait_for_linkup $NIC2

    reset_tc $NIC $REP
    if [ "$TEST_GRE" = 1 ]; then
        add_gre_rule $local_ip $remote_ip
    else
        add_vxlan_rule $local_ip $remote_ip
    fi

    ping_ip="1.1.1.2"
    ifconfig $VF 1.1.1.1/24 up
    ip n add $ping_ip dev $VF lladdr $dst_mac

    title "-- starts with 0"
    get_packets
    if [ "$a" != 0 ]; then
        err "Expected 0 packets"
        return
    fi

    title "-- ping and expect 10 packets"
    do_traffic
    sleep 1 # seems needed for good report
    get_packets
    if [ "$a" -lt 10 ]; then
        err "Expected 10 packets"
        return
    fi
    success

    title "-- port0 down"
    ifconfig $dev1 down
    sleep 2 # wait for neigh update
    
    title "-- ping and expect 20 packets"
    do_traffic
    sleep 1
    get_packets
    if [ "$a" -lt 20 ]; then
        err "Expected 20 packets"
        return
    fi
    success

    title "-- port0 up"
    ifconfig $dev1 up
    wait_for_linkup $dev1
    ip n r $n1 dev $dev1 lladdr e4:1d:2d:31:eb:08

    title "-- port1 down"
    ifconfig $dev2 down
    sleep 2 # wait for neigh update
    
    title "-- ping and expect 30 packets"
    do_traffic
    sleep 1
    get_packets
    if [ "$a" -lt 30 ]; then
        err "Expected 30 packets"
        return
    fi
    success

    title "-- port1 up"
    ifconfig $dev2 up
    ip n add $n2 dev $dev2 lladdr e4:1d:2d:31:eb:08

    reset_tc $REP
}

function do_test() {
    title $1
    eval $1
}


cleanup
config
do_test test_ecmp_rule_stats
echo "cleanup"
cleanup
deconfig_ports
test_done
