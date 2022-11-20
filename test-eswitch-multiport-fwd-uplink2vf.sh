#! /bin/bash

# Verify that we can add rule that forwards traffic from uplink port to a VF of any PF.

my_dir="$(dirname "$0")"
. $my_dir/common.sh

min_nic_cx6dx
require_remote_server

local_ip=6.6.6.5
remote_ip=6.6.6.6

function get_mac {
    cat /sys/class/net/$1/address
}

function cleanup() {
    remote_cleanup
    local_cleanup
}

trap cleanup EXIT

function config_remote {
    local vfmaic=$1
    on_remote "
        ip link set up dev $REMOTE_NIC
        ip link set up dev $REMOTE_NIC2
        ip neigh add $local_ip lladdr $vfmac dev $REMOTE_NIC2
        ip a add ${remote_ip}/24 dev $REMOTE_NIC2
    "
}

function remote_cleanup() {
    on_remote "ip a flush dev $REMOTE_NIC2"
}

function config_local {
    enable_lag_resource_allocation_mode
    set_lag_port_select_mode "multiport_esw"
    config_sriov 1
    config_sriov 1 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    reset_tc $REP $NIC $NIC2
    ip link set up dev $REP
    ip link set up dev $NIC
    ip link set up dev $NIC2
    bind_vfs $NIC0
    ip link set up dev $VF
    ip a add ${local_ip}/24 dev $VF
    tc_filter add dev $NIC2 prot ip root flower dst_ip $local_ip action mirred egress redirect dev $REP
    tc_filter add dev $REP prot ip root flower dst_ip $remote_ip action mirred egress redirect dev $NIC2
}

function local_cleanup {
    reset_tc $NIC $NIC2 $REP
    restore_lag_port_select_mode
    restore_lag_resource_allocation_mode
}

function start_tcpdump() {
    tdpcap=/tmp/$$.pcap
    tcpdump -ni $NIC2 -c 1 -w $tdpcap icmp &
    tdpid=$!
    sleep 1
}

function stop_tcpdump() {
    kill $tdpid 2>/dev/null
    lines=$(tcpdump -r $tdpcap | wc -l)
    echo lines $lines
    if (( lines != 0 )); then
        err "traffic not offloaded"
    fi
    rm $tdpcap
}

config_local
vfmac=$(get_mac $VF)
config_remote $vfmac
remote_mac=$(on_remote cat /sys/class/net/$REMOTE_NIC2/address)
ip n add $remote_ip lladdr $remote_mac dev $VF
start_tcpdump
ping -c 2 $remote_ip || err "ping failed"
stop_tcpdump
cleanup
trap - EXIT
test_done
