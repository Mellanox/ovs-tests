#!/bin/bash
#
# Bug SW #1223798: [ASAP MLNX OFED] Call trace from act_mirred module
# Bug SW #1506933: [upstream] null deref in dev_hard_start_xmit()
#

my_dir="$(dirname "$0")"

function clean_veth() {
    ip link del veth0 2>/dev/null
    ip link del veth1 2>/dev/null
}

trap clean_veth EXIT
clean_veth
ip link add veth0 type veth peer name veth1

FORCE_VF2=veth0
FORCE_REP2=veth1

. $my_dir/test-vf-vf-fwd.sh
