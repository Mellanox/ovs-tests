#!/bin/bash
#
# Bug SW #1341628: Bad rules added when offloading rules to HW
#

NIC=${1:-ens5f0}
FILTER=${FILTER}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


enable_switchdev_if_no_rep $REP

function cleanup() {
    ip link del veth0 2>/dev/null
    ip addr flush dev $REP
}
trap cleanup EXIT

cleanup
ip link add veth0 type veth peer name veth1
tc qdisc add dev veth0 ingress
reset_tc_nic $REP

title "Add tc rule veth->rep and expect to be sw"

tc filter add dev veth0 protocol ip parent ffff: \
        flower \
                dst_mac e4:11:22:11:4a:51 \
            action mirred egress redirect dev $REP || err "Failed adding veth->rep rule"

tc filter show dev veth0 ingress | egrep -z "dst_mac e4:11:22:11:4a:51\s*eth_type ipv4\s*in_hw" && err "Found in_hw rule for veth->rep" || success

reset_tc_nic $REP
test_done
