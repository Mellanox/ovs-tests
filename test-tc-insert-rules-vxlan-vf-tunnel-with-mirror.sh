#!/bin/bash
#
# Verify encap mirroring rules insertion on setup with VF as tunnel endpoint
#
# #2495074: [Upstream][Stacked Devices] Kernel null pointer dereference with vf mirroring
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_nic cx4 cx4lx cx5

config_sriov 3
enable_switchdev
REP3=`get_rep 2`
require_interfaces REP REP2 REP3 NIC
unbind_vfs
bind_vfs
VF3=`get_vf 2`

function test_vxlan_mirror_encap() {
    local ip_src="20.1.11.1"
    local ip_dst="20.1.12.1"
    local vxlan_port="4789"

    vx=vxlan1
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dev $VF1 dstport $vxlan_port external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set dev $vx up
    tc qdisc add dev $vx ingress

    ip addr flush dev $VF1
    ip addr add $ip_src/16 dev $VF1
    ifconfig $VF1 up
    ip neigh replace $ip_dst lladdr e4:11:22:11:55:55 dev $VF1
    ifconfig $NIC up

    reset_tc $NIC $REP

    title "    - encap"
    tc_filter_success add dev $REP protocol 0x806 parent ffff: prio 1 \
                      flower \
                          dst_mac e4:11:22:11:4a:51 \
                          src_mac e4:11:22:11:4a:50 \
                      action mirred egress mirror dev $REP3 pipe \
                      action tunnel_key set \
                          src_ip $ip_src \
                          dst_ip $ip_dst \
                          dst_port $vxlan_port \
                          id 100 \
                      action mirred egress redirect dev $vx

    reset_tc $NIC $REP $vx
    ip neigh del $ip_dst lladdr e4:11:22:11:55:55 dev $VF1
    ip addr flush dev $VF1
    ip link del $vx
}

start_check_syndrome
test_vxlan_mirror_encap

check_for_errors_log
check_syndrome
check_kasan
test_done
