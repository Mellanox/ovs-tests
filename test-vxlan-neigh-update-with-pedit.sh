#!/bin/bash
#
# This is a copied test of test-vxlan-neigh-update.sh but added pedit actions in
# an encap rule to reproduce another issue with rules with encap+header_rewrite
# in the same rule.
#
# Bug SW #1133828: syndrome of invalid encap header id when adding flow without valid neigh
# Bug SW #1120257: KASAN: double-free or invalid-free in mlx5e_detach_encap.isra.16+0x2bd/0x420 [mlx5_core]
# Bug SW #1162546: tc esw modify header logic is broken in the presence of encap / neigh update
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4

REP=`get_rep 0`
if [ -z "$REP" ]; then
    fail "Missing rep $REP"
fi

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

    #
    # encap with header rewrite
    #

    # this reproduced use-after-free error.
    # [Thu Oct 26 17:55:56 2017] BUG: KASAN: use-after-free in mlx5e_attach_mod_hdr.isra.15+0xebf/0xfc0 [mlx5_core]
    #
    tc_filter add dev $REP protocol ip parent ffff: prio 3\
        flower dst_mac $dst_mac $flag \
        action pedit ex \
                munge eth src set 11:22:33:44:55:66 \
                munge eth dst set aa:bb:cc:dd:ee:ff pipe \
        action csum ip pipe \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1

    # this rule should fail as we cannot change ttl in ip proto rule
    # but it reproduced a different error.
    # [Thu Oct 26 17:55:56 2017] BUG: KASAN: use-after-free in mlx5e_attach_mod_hdr.isra.15+0xebf/0xfc0 [mlx5_core]
    #
    tc filter add dev $REP protocol ip parent ffff: prio 4\
        flower dst_mac $dst_mac $flag \
        action pedit ex \
		munge ip ttl set 0x63  \
                munge eth src set 11:22:33:44:55:66 \
                munge eth dst set aa:bb:cc:dd:ee:ff pipe \
        action csum ip pipe \
        action tunnel_key set \
            id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
        action mirred egress redirect dev vxlan1


    # tunnel key unset
    reset_tc vxlan1

    tc_filter add dev vxlan1 protocol ip parent ffff: prio 5\
        flower $flag enc_src_ip ${remote_ip} enc_dst_ip ${local_ip} \
            enc_key_id $id enc_dst_port ${dst_port} \
        action tunnel_key unset \
        action mirred egress redirect dev $REP

    tc_filter add dev vxlan1 protocol arp parent ffff: prio 6\
        flower $flag enc_src_ip ${remote_ip} enc_dst_ip ${local_ip} \
        enc_key_id $id enc_dst_port ${dst_port} \
        action tunnel_key unset \
        action mirred egress redirect dev $REP

    # add change evets
    title "-- forcing addr change 1"
    sleep 5
    ip n replace ${remote_ip} dev $NIC lladdr 11:22:33:44:55:66

    title "-- forcing addr change 2"
    sleep 5
    ip n replace ${remote_ip} dev $NIC lladdr 11:22:33:44:55:99
}


start_check_syndrome

title "Test neigh update ipv4"
cleanup
ip addr add ${local_ip}/24 dev $NIC
neigh_update_test $local_ip $remote_ip

title "Test neigh update ipv6"
cleanup
ip -6 addr add ${local_ip6}/64 dev $NIC
neigh_update_test $local_ip6 $remote_ip6

dmesg | tail -n20 | grep "encap size" | grep "too big"
if [[ $? -ne 0 ]]; then
    err
fi

check_kasan
check_syndrome
test_done
