#!/bin/bash

my_dir="$(dirname "$0")"

ip link add veth0 type veth peer name veth1

FORCE_VF2=veth0
FORCE_REP2=veth1

. $my_dir/test-vf-vf-fwd.sh

ip link del veth0 2>/dev/null
