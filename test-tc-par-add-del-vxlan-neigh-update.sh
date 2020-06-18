#!/bin/bash
#
# This verifies that parallel vxlan rule insert/delete is handled correctly by
# tc during concurrent neigh update event. Tests with large amount of rules
# updated in batch mode to find any potential bugs and race conditions.
#

total=${1:-100000}
rules_per_file=10000

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

echo "setup"
config_sriov 2 $NIC
enable_switchdev
bind_vfs

local_ip="2.2.2.2"
remote_ip="2.2.2.3"
dst_mac="e4:1d:2d:fd:8b:02"
vxlan_mac="e4:1d:2d:fd:8b:04"
flag=skip_sw
dst_port=1234
id=98
vxlan_dev="vxlan1"
neigh_change_times=3


function cleanup() {
    ip link del dev $vxlan_dev 2> /dev/null
    ip link add $vxlan_dev type vxlan id $id dev $NIC dstport $dst_port
    ip link set $vxlan_dev up
    ip n del ${remote_ip} dev $NIC 2>/dev/null
    ifconfig $NIC down
    ip addr flush dev $NIC
}

function change_neigh() {
    local remote_ip="$1"

    sleep 1
    for ((i = 0; i < $neigh_change_times; i++)); do
        arp -s $remote_ip  $vxlan_mac
        sleep 0.5
        arp -d $remote_ip
        sleep 0.5
    done
}

function neigh_update_test() {
    local local_ip="$1"
    local remote_ip="$2"
    local max_rules=$total

    tc_batch_vxlan "dev $NIC" $total $rules_per_file " " $id $local_ip $remote_ip $dst_port $vxlan_dev

    echo "local_ip $local_ip remote_ip $remote_ip"
    ifconfig $NIC up
    reset_tc $NIC
    reset_tc $REP
    reset_tc $vxlan_dev

    echo "Insert rules in parallel"
    change_neigh $remote_ip &
    ls ${TC_OUT}/add.* | xargs -n 1 -P 100 tc $force -b &>/dev/null
    check_num_rules $max_rules $NIC

    sleep 1

    echo "Delete rules in parallel"
    change_neigh $remote_ip &
    ls ${TC_OUT}/del.* | xargs -n 1 -P 100 tc $force -b &>/dev/null
    check_num_rules 0 $NIC

    ip l del $vxlan_dev
}

function test_neigh_update_ipv4() {
    title "Test neigh update ipv4"
    cleanup
    ip addr add ${local_ip}/24 dev $NIC
    neigh_update_test $local_ip $remote_ip
}

start_check_syndrome

test_neigh_update_ipv4

check_kasan
check_syndrome
test_done
