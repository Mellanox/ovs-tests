#!/bin/bash
#
# 1. shuffle tc commands
# 2. check for syndromes
#
# Ths difference from test-tc-shuffle.sh is here the delete is on the parent
# and not single rule.
#
# Bug SW #932484: FW error of groups overlapping when scaling up ovs
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

TMPFILE=/tmp/rules-$$

cat >$TMPFILE <<EOF
tc filter add dev $NIC parent ffff: protocol arp prio 1 flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip prio 2 flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 action mirred egress redirect dev $NIC

tc filter add dev $NIC parent ffff: protocol ip prio 3 flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 ip_proto udp src_port 11636 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip prio 4 flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 ip_proto udp src_port 2229 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip prio 5 flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 ip_proto udp src_port 6822 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip prio 6 flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 ip_proto udp src_port 2009 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip prio 7 flower dst_mac e4:1d:2d:5d:25:35 ip_proto udp src_port 2009 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip prio 8 flower dst_mac e4:1d:2d:5d:25:39 action mirred egress redirect dev $NIC

tc filter del dev $NIC parent ffff:
EOF

title "Test for groups overlapping"
start_check_syndrome
reset_tc_nic $NIC
for i in `seq 100`; do
    `shuf -n1 $TMPFILE` >/dev/null 2>&1
done
reset_tc_nic $NIC
check_syndrome && success || err "Failed"

rm -f $TMPFILE
test_done
