#!/bin/bash
#
# Test traffic between VFs on different nodes configured with OVN and OVS with VF LAG and VLAN then check traffic is offloaded with ipv6 underlay
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-basic-test.sh

NO_TITLE=1

ovn_set_ipv6_ips
. $my_dir/test-ovn-geneve-single-switch-2-nodes-vf-lag-tunnel-vlan.sh
