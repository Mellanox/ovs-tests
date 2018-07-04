#!/bin/bash
#
# Testing we return tc rule stats even if when one port is down.
# In vxlan case it also means there is no rule offloaded.
#
# Bug SW #1431290: [IBM ECMP] intermediate high latency pings when a PF is down
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov 2
require_multipath_support
require_mlxdump
reset_tc_nic $NIC

local_ip="49.0.10.60"
remote_ip="46.0.10.180"
dst_mac="e4:1d:2d:fd:8b:02"
flag=skip_sw
dst_port=4789
id=98
net=`getnet $remote_ip 24`
[ -z "$net" ] && fail "Missing net"


function disable_sriov() {
    echo "- Disable SRIOV"
    echo 0 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 0 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_sriov() {
    echo "- Enable SRIOV"
    echo 2 > /sys/class/net/$NIC/device/sriov_numvfs
    echo 2 > /sys/class/net/$NIC2/device/sriov_numvfs
}

function enable_multipath_and_sriov() {
    local a
    local b
    echo "- Enable multipath"
    a=`cat /sys/class/net/$NIC/device/sriov_numvfs`
    b=`cat /sys/class/net/$NIC2/device/sriov_numvfs`
    if [ $a -eq 0 ] || [ $b -eq 0 ]; then
        disable_sriov
        enable_sriov
    fi
    unbind_vfs $NIC
    unbind_vfs $NIC2
    enable_multipath || err "Failed to enable multipath"
}

function cleanup() {
    ip link del dev vxlan1 2> /dev/null
    ip n del ${remote_ip} dev $NIC 2>/dev/null
    ip n del ${remote_ip6} dev $NIC 2>/dev/null
    ifconfig $NIC down
    ifconfig $NIC2 down
    ip addr flush dev $NIC
    ip addr flush dev $NIC2
    ip l del dummy9 &>/dev/null
    ip r d $net &>/dev/null
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

    tc_filter add dev $REP protocol ip parent ffff: prio 1 \
        flower ip_proto icmp dst_mac $dst_mac $flag \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1
}

dev1=$NIC
dev2=$NIC2
dev1_ip=48.2.10.60
dev2_ip=48.1.10.60
n1=48.2.10.1
n2=48.1.10.1

function config_multipath_route() {
    echo "config multipath route"
    ip l add dev dummy9 type dummy &>/dev/null
    ifconfig dummy9 $local_ip/24
    ifconfig $NIC $dev1_ip/24
    ifconfig $NIC2 $dev2_ip/24
    ip r r $net nexthop via $n1 dev $dev1 nexthop via $n2 dev $dev2
    ip n del $n1 dev $dev1 &>/dev/null
    ip n del $n2 dev $dev2 &>/dev/null
    ip n del $remote_ip dev $dev1 &>/dev/null
    ip n del $remote_ip dev $dev2 &>/dev/null
    ip n add $n1 dev $dev1 lladdr e4:1d:2d:31:eb:08
    ip n add $n2 dev $dev2 lladdr e4:1d:2d:31:eb:08
}

function _reset_multipath() {
    # we currently switch to legacy and back because of an issue
    # when multipath is ready.
    # Bug SW #1391181: [ASAP MLNX OFED] Enabling multipath only becomes enabled
    # when changing mode from legacy to switchdev
    enable_legacy $NIC
    enable_legacy $NIC2
    enable_switchdev $NIC
    enable_switchdev $NIC2
}

function config() {
    enable_multipath_and_sriov
    _reset_multipath
    bind_vfs $NIC
    reset_tc $NIC
    reset_tc $REP
    config_vxlan
    ifconfig $NIC down
    ifconfig $NIC2 down
    ifconfig $NIC up
    ifconfig $NIC2 up
    ifconfig $REP up
    ifconfig $VF up
}

function no_encap_rules() {
    local i=$1
    i=$i && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
    cat /tmp/port$i | tr -d ' ' | grep "action:0x1c" || echo "No encap rule in port$i as expected"
}

function look_for_encap_rules() {
    local ports=$@
    local i
    echo "look for encap rules"
    for i in $ports ; do
        i=$i && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
        cat /tmp/port$i | tr -d ' ' | grep "action:0x1c" || err "Cannot find encap rule in port$i"
    done
    tc -s filter show dev $REP ingress
}

function test_ecmp_rule_stats() {
    config_multipath_route

    title "-- both ports up"
    add_vxlan_rule $local_ip $remote_ip

    ifconfig $NIC up
    ifconfig $NIC2 up
    ifconfig $REP up
    ifconfig $VF up
    wait_for_linkup $NIC
    wait_for_linkup $NIC2
    ping_ip="1.1.1.2"
    ip n add $ping_ip dev $VF lladdr $dst_mac

    title "-- starts with 0"
    tc -s filter show dev $REP ingress | grep bytes
    a=`tc -j -s filter show dev $REP ingress | jq ".[1].options.actions[1].stats.packets"`
    if [ "$a" != 0 ]; then
        err "Expected 0 packets"
        return
    fi

    title "-- ping"
    ping -q -I $VF $ping_ip -i 0.1 -c 10 -w 1
    sleep 1 # seems needed for good report
    tc -s filter show dev $REP ingress | grep bytes
    a=`tc -j -s filter show dev $REP ingress | jq ".[1].options.actions[1].stats.packets"`
    if [ "$a" -lt 10 ]; then
        err "Expected 10 packets"
        return
    fi
    success

    title "-- port0 down"
    ifconfig $dev1 down
    sleep 2 # wait for neigh update
    
    title "-- ping"
    ping -q -I $VF $ping_ip -i 0.1 -c 10 -w 1
    sleep 1
    tc -s filter show dev $REP ingress | grep bytes
    a=`tc -j -s filter show dev $REP ingress | jq ".[1].options.actions[1].stats.packets"`
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
    
    title "-- ping"
    ping -q -I $VF $ping_ip -i 0.1 -c 10 -w 1
    sleep 1
    tc -s filter show dev $REP ingress | grep bytes
    a=`tc -j -s filter show dev $REP ingress | jq ".[1].options.actions[1].stats.packets"`
    if [ "$a" -lt 30 ]; then
        err "Expected 30 packets"
        return
    fi
    success
    title "-- port1 up"
    ifconfig $dev2 up
    ip n add $n2 dev $dev2 lladdr e4:1d:2d:31:eb:08

    reset_tc_nic $REP
}

function do_test() {
    title $1
    eval $1
}


cleanup
config

do_test test_ecmp_rule_stats
test_done
