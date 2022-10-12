#!/bin/bash
#
# This verifies that parallel vxlan rule insert/delete is handled correctly by
# tc during concurrent neigh update event. Tests with large amount of rules
# updated in batch mode to find any potential bugs and race conditions.
#
# Bug SW #2674110: User-after-free in neigh update
#

total=${1:-10000}
rules_per_file=1000
encaps_per_file=200

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

echo "setup"
config_sriov 2 $NIC
enable_switchdev
bind_vfs

local_ip_net="2.2.2."
local_ip_host="1"
remote_ip_net="2.2.3."
remote_ip_host="1"
dst_mac="e4:1d:2d:fd:8b:02"
vxlan_mac="e4:1d:2d:fd:8b:04"
dst_port=1234
id=98
vxlan_dev="vxlan1"
neigh_change_times=5


function cleanup() {
    ip l del $vxlan_dev 2> /dev/null
    ip n del ${remote_ip_net}${remote_ip_host} dev $NIC 2>/dev/null
    ip link set $NIC down
    ip addr flush dev $NIC
}
trap cleanup EXIT

function change_neigh() {
    local ip_net="$1"
    local ip_host_start="$2"
    local ip_host_end="$3"

    sleep 0.01
    for ((i = 0; i < $neigh_change_times; i++)); do
        for ((j = $ip_host_start; j < $ip_host_end; j++)); do
            arp -s ${ip_net}${j} $vxlan_mac
            sleep 0.01
            arp -d ${ip_net}${j}
            sleep 0.01
        done
    done
}

function neigh_update_test() {
    local ip_net="$1"
    local ip_host_start="$2"
    local ip_host_end="$3"
    local t t1 t2 pid

    reset_tc $NIC $REP $vxlan_dev

    title "Insert rules in parallel"
    change_neigh $ip_net $ip_host_start $ip_host_end &
    pid=$!
    t1=`get_ms_time`
    ls ${TC_OUT}/add.* | xargs -n 1 -P 100 tc $force -b &>/dev/null
    t2=`get_ms_time`
    let t=t2-t1
    echo "Took $t ms"
    check_num_rules $total $REP
    kill $pid &>/dev/null
    wait $pid &>/dev/null

    sleep 1

    title "Delete rules in parallel"
    change_neigh $ip_net $ip_host_start $ip_host_end &
    pid=$!
    t1=`get_ms_time`
    ls ${TC_OUT}/del.* | xargs -n 1 -P 100 tc $force -b &>/dev/null
    t2=`get_ms_time`
    let t=t2-t1
    echo "Took $t ms"
    check_num_rules 0 $REP
    kill $pid &>/dev/null
    wait $pid &>/dev/null

    reset_tc $NIC $REP
}

function test_neigh_update_multi_neigh_ipv4() {
    title "Test multi neigh update ipv4"
    local ip_host_end=$((remote_ip_host+encaps_per_file))
    local local_ip=${local_ip_net}${local_ip_host}
    cleanup

    tc_batch_vxlan_multiple_encap_multiple_neigh "dev $REP" $total $rules_per_file \
                                                 "src_ip 192.168.111.1 dst_ip 192.168.111.2 ip_proto udp dst_port 1 src_port 1" \
                                                 $id $local_ip $remote_ip_net $remote_ip_host $dst_port $vxlan_dev \
                                                 $encaps_per_file 0

    echo "local_ip $local_ip remote_ip ${remote_ip_net}${remote_ip_host}"
    ip link del dev $vxlan_dev 2> /dev/null
    ip link add $vxlan_dev type vxlan id $id dev $NIC dstport $dst_port
    ip link set $vxlan_dev up
    ip link set $NIC up
    ip link set $REP up
    ip addr add $local_ip/16 dev $NIC

    for i in {1..2}; do
        neigh_update_test $remote_ip_net $remote_ip_host $ip_host_end
    done
}

function test_neigh_update_single_neigh_ipv4() {
    title "Test single neigh update ipv4"
    local ip_host_end=$((remote_ip_host+1))
    local remote_ip=${remote_ip_net}${remote_ip_host}
    cleanup

    tc_batch_vxlan_multiple_encap_single_neigh "dev $REP" $total $rules_per_file \
                                               "src_ip 192.168.111.1 dst_ip 192.168.111.2 ip_proto udp dst_port 1 src_port 1" \
                                               $id $local_ip_net $local_ip_host $remote_ip $dst_port $vxlan_dev \
                                               $encaps_per_file 0

    echo "local_ip ${local_ip_net}${local_ip_host} remote_ip $remote_ip"
    ip link del dev $vxlan_dev 2> /dev/null
    ip link add $vxlan_dev type vxlan id $id dev $NIC dstport $dst_port
    ip link set $vxlan_dev up
    ip link set $NIC up
    ip link set $REP up

    for ((i=$local_ip_host; i<$encaps_per_file+$local_ip_host; i++)); do
        ip addr add ${local_ip_net}${i}/16 dev $NIC
    done
    for i in {1..2}; do
        neigh_update_test $remote_ip_net $remote_ip_host $ip_host_end
    done
}


test_neigh_update_single_neigh_ipv4
test_neigh_update_multi_neigh_ipv4

test_done
