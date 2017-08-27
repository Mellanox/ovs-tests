#!/bin/bash
#
# 1. shuffle tc commands with duplicates (no prios)
#    - can have syndrome for duplicate
# 2. check for errors
#
# Ths difference from test-tc-shuffle-2.sh is we dont specify prios so
# hw can get duplicate rule.
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

TMPFILE=/tmp/rules-$$

#
# No prios on purpose.
# 
cat >$TMPFILE <<EOF
tc filter add dev $NIC parent ffff: protocol arp flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 action mirred egress redirect dev $NIC

tc filter add dev $NIC parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 ip_proto udp src_port 11636 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 ip_proto udp src_port 2229 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 ip_proto udp src_port 6822 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 ip_proto udp src_port 2009 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:25:35 ip_proto udp src_port 2009 action mirred egress redirect dev $NIC
tc filter add dev $NIC parent ffff: protocol ip flower dst_mac e4:1d:2d:5d:25:39 action mirred egress redirect dev $NIC

tc filter del dev $NIC parent ffff:
EOF

title "Test for groups overlapping"
reset_tc_nic $NIC
for i in `seq 100`; do
    `shuf -n1 $TMPFILE` >/dev/null 2>&1
done
reset_tc_nic $NIC
sec=`get_test_time_elapsed`
a=`journalctl -n20 --since="$sec seconds ago" | grep -v 0xd5ef2 | grep -m1 syndrome || true`
if [ "$a" != "" ]; then
    err $a
fi

test_done
