#!/bin/bash
#
# Check the effect of the order of creating tunnel device ingress qdisc
# relative to switching to switchdev mode. There is currenlty a bug in upstream
# kernel that if the qdisc of the tunnel device is created prior to switching
# to switchdev we will not be able to use hardware offloading.
# Bug SW #2678854: OVN HW Offload: Geneve traffic without Connection Tracking is partially offloaded

my_dir="$(dirname "$0")"
. $my_dir/common.sh

trap cleanup EXIT

function cleanup() {
    ip link del dev vxlan0 > /dev/null 2>&1
}

config_sriov
enable_legacy
ip link add dev vxlan0 type vxlan dstport 4789 external
tc qdisc add dev vxlan0 ingress
ip link set up dev vxlan0
enable_switchdev
ip addr add 7.7.7.9/24 dev $NIC
ip link set up dev $NIC
tc_filter add dev vxlan0 prot all prio 5 root flower enc_src_ip 7.7.7.10 enc_dst_ip 7.7.7.9 enc_dst_port 4789 enc_key_id 100 action tunnel_key unset action mirred egress redirect dev $REP
verify_in_hw vxlan0 5

test_done
