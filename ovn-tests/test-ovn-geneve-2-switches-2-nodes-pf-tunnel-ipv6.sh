#!/bin/bash
#
# Verify no traffic between VFs on different nodes configured with OVN 2 isolated switches with ipv6 underlay
#

my_dir="$(dirname "$0")"
. $my_dir/common-ovn-test-utils.sh

NO_TITLE=1

ovn_set_ipv6_ips
. $my_dir/test-ovn-geneve-2-switches-2-nodes-pf-tunnel.sh
