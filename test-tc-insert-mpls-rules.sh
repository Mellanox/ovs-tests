#!/bin/bash
#
# Test rule mpls over udp rules
#

my_dir="$(dirname "$0")"
source $my_dir/common.sh
require_module bareudp

# set test variables
UDPPORT=6635
LABEL=555

function cleanup() {
    ip link del dev bareudp0 2>/dev/null
    ip addr flush dev $NIC 2>/dev/null
    reset_tc $REP
}
trap cleanup EXIT

cleanup

title "Test decap mpls over udp rule and forward to VF rep"
enable_switchdev_if_no_rep $REP

# create tunnel interface
ip link add dev bareudp0 type bareudp dstport $UDPPORT ethertype 0x8847
tc qdisc add dev bareudp0 ingress

# bring up interfaces
ip link set up dev bareudp0
ip link set up dev $REP
reset_tc $NIC

tc_filter add dev bareudp0 protocol mpls_uc prio 1 ingress flower mpls_label $LABEL enc_dst_port $UDPPORT enc_key_id $LABEL action mpls pop protocol ip pipe action pedit ex munge eth dst set 00:11:22:33:44:21 pipe action mirred egress redirect dev $REP

verify_in_hw bareudp0 1

title "Check hardware tables..."
hexport=$(printf "%x" $UDPPORT)
mlxdump -d $PCI fsdump --type FT > /tmp/_fsdump
if grep "outer_headers.udp_dport.*0xffff$" /tmp/_fsdump > /dev/null &&
   grep "outer_headers.udp_dport.*${hexport}$" /tmp/_fsdump > /dev/null; then
    success
else
    err
fi

# set tunnel addressing
ip addr add 8.8.8.21/24 dev $NIC
ip link set up dev $NIC
ip neigh add 8.8.8.24 lladdr 00:11:22:33:44:55 dev $NIC

tc_filter add dev $REP protocol ip prio 1 root flower skip_sw src_ip 2.2.2.21 dst_ip 2.2.2.24 action tunnel_key set src_ip 8.8.8.21 dst_ip 8.8.8.24 id $LABEL dst_port $UDPPORT tos 4 ttl 6 csum action mpls push protocol mpls_uc label $LABEL tc 3 action mirred egress redirect dev bareudp0
verify_in_hw $REP 1

title "Check hardware tables..."
mlxdump -d $PCI fsdump --type FT > /tmp/_fsdump
if grep -q "outer_headers.src_ip_31_0.*0x02020215$" /tmp/_fsdump &&
   grep -q "outer_headers.dst_ip_31_0.*0x02020218$" /tmp/_fsdump &&
   grep -q "action.*0x1c$" /tmp/_fsdump; then
    success
else
    err
fi

reset_tc $NIC

test_done
