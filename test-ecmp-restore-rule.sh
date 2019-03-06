#!/bin/bash
#
# Testing rules added when one port is down are restored when port is up.
#
# Bug SW #1318772: [ASAP-ECMP MLNX OFED] Traffic not offloaded after failover and failback
# Bug SW #1403698: [ECMP] kernel warning: BUG: sleeping function called from invalid context at mm/slab.h:421
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


function cleanup() {
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

function add_vxlan_rule() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    tc_filter add dev $REP protocol arp parent ffff: prio 1 \
        flower dst_mac $dst_mac skip_sw \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1
}

function config() {
    config_ports
    config_vxlan
}

function test_restore_rule() {
    config_multipath_route
    is_vf_lag_active || return 1

    reset_tc $REP

    title "-- both ports up"
    log "add rule"
    add_vxlan_rule $local_ip $remote_ip
    look_for_encap_rules 0 1
    reset_tc $REP

    title "-- port0 down"
    ifconfig $NIC down
    log "add rule"
    add_vxlan_rule $local_ip $remote_ip
    no_encap_rules 0
    look_for_encap_rules 1

    title "-- port0 up"
    ifconfig $NIC up
    wait_for_linkup $NIC
    ip n r $n1 dev $dev1 lladdr $n_mac
    sleep 2 # wait for neigh update
    look_for_encap_rules 0 1
    reset_tc $REP

    title "-- port1 down"
    ifconfig $NIC2 down
    log "add rule"
    add_vxlan_rule $local_ip $remote_ip
    look_for_encap_rules 0
    no_encap_rules 1

    title "-- port1 up"
    ifconfig $NIC2 up
    wait_for_linkup $NIC2
    ip n r $n2 dev $dev2 lladdr $n_mac
    sleep 2 # wait for neigh update
    look_for_encap_rules 0 1
    reset_tc $REP
}

function do_test() {
    title $1
    eval $1
}


cleanup
config
do_test test_restore_rule
echo "cleanup"
cleanup
deconfig_ports
test_done
