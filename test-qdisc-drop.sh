#!/bin/bash
#
# Test issue qdisc dropping packets
# [PATCH net 1/1] net: Fix return value of qdisc ingress handling on success
#
# Bug SW #3192804: HBN ipv4 numbered neighbors are flapping - ovs offload issue

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function cleanup() {
    killall -q iperf3
    ip link del veth1 2>/dev/null
    ip link del veth2 2>/dev/null
    ip -all netns delete
}

trap cleanup EXIT

title "Config"
ip link add veth1 type veth peer name peer1
ip link add veth2 type veth peer name peer2
ifconfig peer1 5.5.5.6/24 up
ip netns add ns0
ip link set dev peer2 netns ns0
ip netns exec ns0 ifconfig peer2 5.5.5.5/24 up
ifconfig veth2 0 up
ifconfig veth1 0 up

title "ingress forwarding veth1 <-> veth2"
tc qdisc add dev veth2 ingress
tc qdisc add dev veth1 ingress
tc filter add dev veth2 ingress prio 1 proto all flower action mirred egress redirect dev veth1
tc filter add dev veth1 ingress prio 1 proto all flower action mirred egress redirect dev veth2

title "verify connection"
iperf3 -s -D
ip netns exec ns0 iperf3 -c 5.5.5.6 -i 1 -t 2 || err "iperf failed"

title "steal packet from peer1 egress to veth2 ingress, bypassing the veth pipe"
tc qdisc add dev peer1 clsact
tc filter add dev peer1 egress prio 20 proto ip flower action mirred ingress redirect dev veth1

title "run iperf and verify connection is still working"
ip netns exec ns0 iperf3 -c 5.5.5.6 -i 1 -t 2 --connect-timeout 2 || err "iperf failed"

trap - EXIT
cleanup
test_done
