#!/bin/bash
#
# Verify traffic between VFs on different nodes configured with OVN router and 2 switches is offloaded with ipv6 underlay
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-basic-test.sh

NO_TITLE=1

ovn_set_ipv6_ips
. $my_dir/test-ovn-geneve-single-router-2-switches-2-nodes-vf-lag-tunnel-vlan.sh
