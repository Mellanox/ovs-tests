#! /bin/bash

# Verify that we can add rule that forwards traffic from VF to uplink1 and uplink2.

my_dir="$(dirname "$0")"
. $my_dir/common.sh

min_nic_cx6dx
require_remote_server

local_ip=6.6.6.5
remote_ip=6.6.6.6

function get_mac() {
    cat /sys/class/net/$1/address
}

function cleanup() {
    local_cleanup
}

trap cleanup EXIT

function config_remote() {
    local nic=$1
    local vfmac=$(get_mac $VF)
    on_remote "ip link set up dev $nic
               ip neigh r $local_ip dev $nic lladdr $vfmac
               ip a r ${remote_ip}/24 dev $nic"
}

function cleanup_remote() {
    local nic=$1
    on_remote "ip a flush dev $nic"
}

function config_local() {
    enable_lag_resource_allocation_mode
    set_lag_port_select_mode "multiport_esw"
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    reset_tc $REP $NIC $NIC2
    enable_esw_multiport

    ip link set up dev $REP
    ip link set up dev $NIC
    ip link set up dev $NIC2
    bind_vfs
    ip link set up dev $VF
}

function local_cleanup() {
    reset_tc $NIC $NIC2 $REP
    disable_esw_multiport
    restore_lag_port_select_mode
    restore_lag_resource_allocation_mode
    enable_legacy $NIC2
    config_sriov 0 $NIC2
}

function start_tcpdump() {
    title "start tcpdump"
    tdpcap=/tmp/$$.pcap
    tcpdump -ni $NIC2 -c 1 -w $tdpcap icmp &
    tdpid=$!
    sleep 1
}

function stop_tcpdump() {
    title "stop tcpdump"
    kill $tdpid 2>/dev/null
    wait
    local lines=$(tcpdump -r $tdpcap | wc -l)
    echo lines $lines
    if (( lines != 0 )); then
        err "traffic not offloaded"
    fi
    rm $tdpcap
}

function config_test() {
    local nic=$1

    config_remote $nic
    ip a r ${local_ip}/24 dev $VF
    local remote_mac=$(on_remote cat /sys/class/net/$nic/address)
    ip neigh r $remote_ip lladdr $remote_mac dev $VF

    title "config rules"
    tc_filter add dev $nic prot ip ingress flower skip_sw dst_ip $local_ip action mirred egress redirect dev $REP
    tc_filter add dev $REP prot ip ingress flower skip_sw dst_ip $remote_ip action mirred egress redirect dev $nic
}

function test_ping() {
    local nic=$1
    config_test $nic
    start_tcpdump
    sleep 0.5

    title "test ping $nic"
    ping -c 2 $remote_ip || err "ping failed"
    stop_tcpdump
    cleanup_remote $nic
    reset_tc $nic $REP
}

config_local
test_ping $NIC
test_ping $NIC2
trap - EXIT
cleanup
test_done
