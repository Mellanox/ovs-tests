#!/bin/bash
#
# Bug SW #2771481: [NGN OVN RoCE SMB Direct BF2] Call trace mlx5_eswitch_del_offloaded_rule 


my_dir="$(dirname "$0")"
. $my_dir/common.sh

config_sriov
enable_switchdev
bind_vfs

local_ip="2.2.2.2"
remote_ip="2.2.2.3"
local_ip6="2002:0db8:0:f101::1"
remote_ip6="2002:0db8:0:f101::2"
dst_mac="e4:1d:2d:fd:8b:02"
flag=skip_sw
dst_port=1234
id=98

function config() {
    ip link add vxlan1 type vxlan id $id dev $NIC dstport $dst_port
    ip link set vxlan1 up
}

function cleanup() {
    ip link del dev vxlan1 2> /dev/null
    ip n del ${remote_ip} dev $NIC 2>/dev/null
    ip n del ${remote_ip6} dev $NIC 2>/dev/null
    ifconfig $NIC down
    ip addr flush dev $NIC
    reset_tc $REP
}
trap cleanup EXIT

function neigh_update_test() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    # tunnel key set
    ifconfig $NIC up
    reset_tc $NIC
    reset_tc $REP

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
        action ct clear pipe \
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

    # add change evets
    for i in `seq 4`; do
        title "-- forcing addr change 1"
        sleep 1
        ip n replace ${remote_ip} dev $NIC lladdr 11:22:33:44:55:66

        title "-- forcing addr change 2"
        sleep 1
        ip n replace ${remote_ip} dev $NIC lladdr 11:22:33:44:55:99
    done
}

function test_neigh_update_ipv4() {
    title "Test neigh update ipv4"
    cleanup
    config
    ip addr add ${local_ip}/24 dev $NIC
    neigh_update_test $local_ip $remote_ip
    cleanup
}

function test_neigh_update_ipv6() {
    title "Test neigh update ipv6"
    # ConnectX-4 Lx doesn't support vxlan over ipv6 tunnel
    if [ "$short_device_name" == "cx4lx" ]; then
        echo "Not relevant for ConnectX-4"
        return
    fi
    cleanup
    config
    ip -6 addr add ${local_ip6}/64 dev $NIC
    neigh_update_test $local_ip6 $remote_ip6
    cleanup
}


start_check_syndrome

test_neigh_update_ipv4
test_neigh_update_ipv6

check_syndrome
test_done
