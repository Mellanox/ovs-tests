#!/bin/bash
#
# Verify traffic between VFs on different nodes configured with OVN router and 2 switches is offloaded with ipv6 underlay
#

my_dir="$(dirname "$0")"

IS_IPV6_UNDERLAY=1
NO_TITLE=1

. $my_dir/test-ovn-geneve-single-router-2-switches-2-nodes-pf-tunnel.sh
