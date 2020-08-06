#!/bin/bash
#
# Test ecmp load balance
#
# Bug SW # 1747774 : [OFED 4.6] Load balancing not working over VF LAG configuration
# Bug SW # 1755805 : [ECMP MOFED 4.6] - Load balance not working at all on TX side over ECMP Configuration

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-ecmp.sh

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
        flower dst_mac $dst_mac skip_sw \
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

function do_traffic() {
    for i in $cores; do
        taskset -c $i timeout 5 iperf -u -c $ping_ip -t 5 -l 512 -P 2 >/dev/null &
    done
    sleep 6
    killall -9 iperf &>/dev/null
    killall -9 iperf &>/dev/null
}

function test_ecmp_load_balance() {
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

    cores=`cat /proc/cpuinfo |grep core\ id | awk {'print $4'}|sort -g|uniq`

    ping_ip="1.1.1.2"
    ifconfig $VF 1.1.1.1/24 up
    ip n add $ping_ip dev $VF lladdr $dst_mac

    title "-- ping and expects packets on both uplinks"
    pkts1=`get_tx_pkts $NIC`
    pkts2=`get_tx_pkts $NIC2`
    do_traffic
    pkts3=`get_tx_pkts $NIC`
    pkts4=`get_tx_pkts $NIC2`

    let diff1=pkts3-pkts1
    let diff2=pkts4-pkts2

    if [ $diff1 -lt 100 ]; then
        err "Expected traffic on $NIC but got only $diff1 packets"
    else
        success "Got $diff1 packets on $NIC"
    fi

    if [ $diff2 -lt 100 ]; then
        err "Expected traffic on $NIC2 but got only $diff2 packets"
    else
        success "Got $diff2 packets on $NIC2"
    fi

    reset_tc $REP
}

function do_test() {
    title $1
    eval $1
}


cleanup
config
do_test test_ecmp_load_balance
echo "cleanup"
cleanup
deconfig_ports
test_done
