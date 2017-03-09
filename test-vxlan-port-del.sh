#!/bin/sh
#
# Test that verified DELETE_VXLAN_UDP_DPORT syndrome
#
# Bug SW #989230: DELETE_VXLAN_UDP_DPORT failed when restart ovs in vxlan with
# non-default port
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


NON_STANDARD_PORT=1234
IFACE=vxlan1

ip link del $IFACE >/dev/null 2>&1


title "Test for DELETE_VXLAN_UDP_DPORT"

title "-- up/del"
start_check_syndrome
ip link add $IFACE type vxlan dstport $NON_STANDARD_PORT external
ip link set $IFACE up
ip link del $IFACE
check_syndrome && success || err

title "-- up/down"
start_check_syndrome
ip link add $IFACE type vxlan dstport $NON_STANDARD_PORT external
ip link set $IFACE up
ip link set $IFACE down
sleep 1
check_syndrome && success || err

title "-- del"
start_check_syndrome
ip link del $IFACE
check_syndrome && success || err

check_kasan
done2
