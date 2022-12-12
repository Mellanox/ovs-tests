#!/bin/bash
#
# Test traffic VM to VM on same subnet different nodes with IPv6 tunnel over vlan configured with OSP and OVN then verify traffic is offloaded
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-osp-test.sh

NO_TITLE=1

ovn_set_ipv6_ips
. $my_dir/test-ovn-osp-vm-vm-same-subnet-2-nodes-pf-tunnel-vlan-int.sh
