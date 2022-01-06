#!/bin/bash
#
# Verify no traffic between VFs on different nodes configured with OVN 2 isolated switches with ipv6 underlay
#

my_dir="$(dirname "$0")"

IS_IPV6_UNDERLAY=1
NO_TITLE=1

. $my_dir/test-ovn-geneve-2-switches-2-nodes-pf-tunnel.sh
