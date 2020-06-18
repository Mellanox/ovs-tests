#!/bin/bash
#
# Test rule of forwarding traffic received from uplink back to uplink
#

my_dir="$(dirname "$0")"
source $my_dir/common.sh

# set test variables
UPLSRC=$NIC
UPLDEST=$NIC

title "Test redirect rule from uplink on esw0 back to the same uplink"
enable_switchdev

# bring up interfaces
ip link set up dev $UPLSRC
ip link set up dev $UPLDEST
reset_tc $UPLSRC

tc_filter add dev $UPLSRC protocol ip prio 1 root flower dst_ip 11.12.13.14 skip_sw action mirred egress redirect dev $UPLDEST

title "Check hardware tables..."
mlxdump -d $PCI fsdump --type FT > /tmp/_fsdump
if cat /tmp/_fsdump | grep -B 44 -A 57 "outer_headers.dst_ip_31_0.*:0x0b0c0d0e" | grep "destination\[0\].destination_type.*:FLOW_TABLE_" > /dev/null; then
    success
else
    err
fi

reset_tc $UPLSRC

test_done
