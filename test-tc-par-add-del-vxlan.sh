#!/bin/bash
#
# This verifies that parallel vxlan rule insert/delete to distinct encap
# entries. Tests with large amount of rules updated in batch mode to find any
# potential bugs and race conditions.
#

total=${1:-100000}
rules_per_file=10000
encaps_per_file=10

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/tc_tests_common.sh

echo "setup"
config_sriov 2 $NIC
enable_switchdev_if_no_rep $REP
bind_vfs

local_ip="2.2.2.2"
remote_ip_net="2.2.2."
remote_ip_host="3"
dst_mac="e4:1d:2d:fd:8b:02"
vxlan_mac="e4:1d:2d:fd:8b:04"
flag=skip_sw
dst_port=1234
id=98
vxlan_dev="vxlan1"


function cleanup() {
    ip link del dev $vxlan_dev 2> /dev/null
    ip link add $vxlan_dev type vxlan id $id dev $NIC dstport $dst_port
    ip link set $vxlan_dev up
    ip n del ${remote_ip_net}${remote_ip_host} dev $NIC 2>/dev/null
    ifconfig $NIC down
    ip addr flush dev $NIC
}

function set_neighs() {
    local remote_ip_net="$1"
    local remote_ip_host="$2"
    local clear="$3"

    # Add neigh for every second encap to test both neigh valid and invalid cases
    for ((i = 0; i < encaps_per_file/2; i++)); do
        if [ "$clear" == 1 ]
        then ip neigh del ${remote_ip_net}${remote_ip_host} dev $NIC
        else ip neigh add ${remote_ip_net}${remote_ip_host} lladdr ${vxlan_mac} dev $NIC
        fi

        ((remote_ip_host+=2))
    done
}

function run_test() {
    local local_ip="$1"
    local remote_ip_net="$2"
    local remote_ip_host="$3"
    local max_rules=$total

     tc_batch_vxlan_multiple_encap "dev $NIC" $total $rules_per_file $id $local_ip $remote_ip_net $remote_ip_host $dst_port $vxlan_dev 10

    echo "local_ip $local_ip remote_ip_net $remote_ip_net"
    ifconfig $NIC up
    reset_tc $NIC
    reset_tc $REP
    reset_tc $vxlan_dev

    set_neighs $remote_ip_net $remote_ip_host 0

    echo "Insert rules in parallel"
    ls ${TC_OUT}/add.* | xargs -n 1 -P 100 tc $force -b &>/dev/null
    check_num_rules $max_rules $NIC

    echo "Delete rules in parallel"
    ls ${TC_OUT}/del.* | xargs -n 1 -P 100 tc $force -b &>/dev/null
    check_num_rules 0 $NIC

    set_neighs $remote_ip_net $remote_ip_host 1
    ip l del $vxlan_dev
}

function test_par_vxlan_ipv4() {
    title "Parallel rule update with multiple encaps"
    cleanup
    ip addr add ${local_ip}/24 dev $NIC
    run_test $local_ip $remote_ip_net $remote_ip_host
}

start_check_syndrome

test_par_vxlan_ipv4

check_kasan
check_syndrome
test_done
