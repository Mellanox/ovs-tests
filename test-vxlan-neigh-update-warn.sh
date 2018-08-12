#!/bin/bash
#
# Test to reproduce warn_on() in mlx5e_tc_update_neigh_used_value()
#
# Bug SW #1324532: Getting warn_on msgs "The neighbour already freed" randomly.
# Bug SW #1431299: [IBM ECMP] Call trace when bringing down a PF
# Bug SW #1435023: [OFED 4.4] Call trace with up/down events on bridge device
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev_if_no_rep $REP
bind_vfs

local_ip="2.2.2.2"
remote_ip="2.2.2.3"
local_ip6="2002:0db8:0:f101::1"
remote_ip6="2002:0db8:0:f101::2"
dst_mac="e4:1d:2d:fd:8b:02"
flag=skip_sw
dst_port=1234
id=98


function cleanup() {
    ip link del dev vxlan1 2> /dev/null
    ip link add vxlan1 type vxlan id $id dev $NIC dstport $dst_port
    ip link set vxlan1 up
    ip n del ${remote_ip} dev $NIC 2>/dev/null
    ip n del ${remote_ip6} dev $NIC 2>/dev/null
    ifconfig $NIC down
    ip addr flush dev $NIC
}

function tc_filter() {
    eval2 tc filter $@
}

function neigh_update_test() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    ifconfig $NIC up
    reset_tc $NIC
    reset_tc $REP
    wait_for_linkup $NIC

    # tunnel key set

    tc_filter add dev $REP protocol arp parent ffff: prio 1\
        flower dst_mac ff:ff:ff:ff:ff:ff $flag \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1

    tc_filter add dev $REP protocol arp parent ffff: prio 2\
        flower dst_mac $dst_mac $flag \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1

    tc_filter add dev $REP protocol ip parent ffff: prio 3\
        flower dst_mac $dst_mac $flag \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1

    # tunnel key unset
    reset_tc vxlan1

    tc_filter add dev vxlan1 protocol ip parent ffff: prio 4\
        flower enc_src_ip ${remote_ip} enc_dst_ip ${local_ip} \
            enc_key_id $id enc_dst_port ${dst_port} \
        action tunnel_key unset \
        action mirred egress redirect dev $REP

    tc_filter add dev vxlan1 protocol arp parent ffff: prio 5\
        flower enc_src_ip ${remote_ip} enc_dst_ip ${local_ip} \
        enc_key_id $id enc_dst_port ${dst_port} \
        action tunnel_key unset \
        action mirred egress redirect dev $REP

    for i in `seq 20` ; do
        echo "-- neigh events $i"
        # add change evets
        # "-- forcing addr change 1"
        ip n replace ${remote_ip} dev $NIC lladdr 11:22:33:44:55:66
        sleep 5

        # "-- link down"
        ifconfig $NIC down
        sleep 1
        # "-- link up"
        ifconfig $NIC up
        wait_for_linkup $NIC

        local m="The neighbour already freed"
        local sec=`get_test_time_elapsed`
        local a=`journalctl --since="$sec seconds ago" | grep -i "$m"`
        if [ "$a" != "" ] ; then
            err $a
            break
        fi
    done

    ip l del vxlan1
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
