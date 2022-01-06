#!/bin/bash
#
# Test fragmented traffic between VFs on different nodes configured with OVN and OVS then check traffic is not offloaded with ipv6 underlay
#

my_dir="$(dirname "$0")"

IS_IPV6_UNDERLAY=1
NO_TITLE=1

. $my_dir/test-ovn-geneve-single-switch-2-nodes-pf-tunnel-fragmented.sh
