#!/bin/bash
#
# Test to verify if we can add vxlan decap + rewrite ipv6 icmp inner rule
# SW #1585031 encapsulated ipv6 rules with header rewrite and decap is offloaded not as expected.

my_dir="$(dirname "$0")"
. $my_dir/common.sh

VXLAN=vxlan1
TUN_SRC_V4=20.1.184.1
TUN_DST_V4=20.1.183.1
VM_DST_MAC=e4:11:22:33:44:70

config_sriov 2
enable_switchdev
bind_vfs

title "Verify we cannot add vxlan decap + rewrite ipv6 icmp inner rule"

ip link del $VXLAN &>/dev/null
ip link add $VXLAN type vxlan dstport 4789 udp6zerocsumrx vni 100 || fail "Failed to create vxlan interface"
ifconfig $VXLAN up
ip addr add dev $NIC $TUN_SRC_V4/16
reset_tc $VXLAN $NIC

# decap rule set on the vxlan device
#58 - icmpv6
tc_filter add dev $VXLAN protocol ipv6 parent ffff: prio 10 \
    flower dst_mac ea:f2:3a:ea:56:f6 src_mac 42:07:44:d8:60:00 \
    enc_src_ip $TUN_DST_V4 enc_dst_ip $TUN_SRC_V4 \
    enc_dst_port 4789 ip_proto 58 enc_key_id 100 \
        action tunnel_key unset \
        action pedit ex munge eth src set 11:22:33:44:55:66 munge ip6 src set 2001:0db8:85a3::8a2e:0370:7335 pipe \
        action csum ip pipe \
        action mirred egress redirect dev $REP

verify_not_in_hw $VXLAN 10 || fail "Expected not_in_hw rule header rewrite after decap to non-supported protocols icmp v6"

reset_tc $NIC
ip addr flush dev $NIC
ip link del $VXLAN

test_done
