#!/bin/bash
#
# Test TC priorities support
# Check we can add multiple masks to the same prio.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev
unbind_vfs
bind_vfs

port1=$VF1
port2=$REP
port3=$VF2
port4=$REP2

require_interfaces port1 port2 port3 port4

function cleanup() {
    ip netns del red &> /dev/null
    ip netns del blue &> /dev/null
    ip addr flush dev $port2
    ip addr flush dev $port4
}
trap cleanup EXIT

cleanup

title "Test TC priorities"

echo "setup netns"
ip netns add red
ip netns add blue
ip link set $port1 netns red
ip link set $port3 netns blue
ip netns exec red ifconfig $port1 mtu 1400 up
ip netns exec blue ifconfig $port3 mtu 1400 up
ip netns exec red ip addr add 1.1.1.1/24 dev $port1
ip netns exec red ip addr add 1.1.1.2/24 dev $port1
ip netns exec red ip addr add 1.1.1.3/24 dev $port1
ip netns exec red ip addr add 1.1.1.4/24 dev $port1
ip netns exec red ip addr add 1.1.1.5/24 dev $port1
ip netns exec blue ip addr add 1.1.1.6/24 dev $port3
ip netns exec blue ip addr add 1.1.1.7/24 dev $port3
ip netns exec blue ip addr add 1.1.1.8/24 dev $port3
ip netns exec blue ip addr add 1.1.1.9/24 dev $port3
ip netns exec blue ip addr add 1.1.1.10/24 dev $port3
ifconfig $port2 up
ifconfig $port4 up

echo "clean devices"
reset_tc $port2
reset_tc $port4

dst_mac=`ip netns exec blue ip link show $VF2 | grep ether | awk '{print $2}'`

start_check_syndrome

skip=skip_sw
#pass '* -> 7-8' or '1-2 -> *'
tc_filter add dev $port2 ingress protocol ip prio 1 flower $skip dst_mac $dst_mac dst_ip 1.1.1.8 action mirred egress redirect dev $port4
tc_filter add dev $port2 ingress protocol ip prio 1 flower $skip dst_mac $dst_mac dst_ip 1.1.1.7 action mirred egress redirect dev $port4
#
# Without the TC priorities patches we fail here
# since prio exists and the mask is different.
#
tc_filter add dev $port2 ingress protocol ip prio 1 flower $skip dst_mac $dst_mac src_ip 1.1.1.1 action mirred egress redirect dev $port4
tc_filter add dev $port2 ingress protocol ip prio 1 flower $skip dst_mac $dst_mac src_ip 1.1.1.2 action mirred egress redirect dev $port4
fail_if_err "TC multi masks per prio is not supported"
#pass '3 -> 6'
tc_filter add dev $port2 ingress protocol ip prio 2 flower $skip dst_mac $dst_mac src_ip 1.1.1.3 dst_ip 1.1.1.6 action mirred egress redirect dev $port4
#drop otherwise
tc_filter add dev $port2 ingress protocol ip prio 3 flower $skip dst_mac $dst_mac action drop

#arp and reverse traffic (skip_hw)
tc_filter add dev $port4 ingress protocol ip  prio 5 flower skip_hw action mirred egress redirect dev $port2
tc_filter add dev $port2 ingress protocol arp prio 4 flower skip_hw action mirred egress redirect dev $port4
tc_filter add dev $port4 ingress protocol arp prio 4 flower skip_hw action mirred egress redirect dev $port2

# fail test if we couldn't add all rules
fail_if_err

# generate traffic
ip netns exec red timeout 0.25 ping -q -I 1.1.1.3 -i 0.25 -W 0.25 -c 1 1.1.1.7 || err "ping failed"
ip netns exec red timeout 0.25 ping -q -I 1.1.1.3 -i 0.25 -W 0.25 -c 1 1.1.1.8 || err "ping failed"
ip netns exec red timeout 0.25 ping -q -I 1.1.1.3 -i 0.25 -W 0.25 -c 1 1.1.1.6 || err "ping failed"

ip netns exec red timeout 0.25 ping -q -I 1.1.1.1 -i 0.25 -W 0.25 -c 1 1.1.1.6 || err "ping failed"
ip netns exec red timeout 0.25 ping -q -I 1.1.1.2 -i 0.25 -W 0.25 -c 1 1.1.1.6 || err "ping failed"
ip netns exec red timeout 0.25 ping -q -I 1.1.1.3 -i 0.25 -W 0.25 -c 1 1.1.1.6 || err "ping failed"

#drops
ip netns exec red timeout 0.25 ping -q -I 1.1.1.3 -i 0.25 -W 0.25 -c 1 1.1.1.9 && err "expected to fail ping"
ip netns exec red timeout 0.25 ping -q -I 1.1.1.4 -i 0.25 -W 0.25 -c 1 1.1.1.9 && err "expected to fail ping"
ip netns exec red timeout 0.25 ping -q -I 1.1.1.5 -i 0.25 -W 0.25 -c 1 1.1.1.9 && err "expected to fail ping"

reset_tc $port2
reset_tc $port4

check_syndrome
test_done
