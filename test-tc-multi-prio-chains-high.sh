#!/bin/bash
#
# Test TC priorities and chains offload support for higher prios and chains
# This is to verify we have the new series that removed the limit for 4 chains.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


enable_switchdev_if_no_rep $REP
unbind_vfs
set_eswitch_inline_mode_transport
bind_vfs

port1=$VF1
port2=$REP
port3=$VF2
port4=$REP2

require_interfaces port1 port2 port3 port4

function cleanup() {
    tc qdisc del dev $port2 ingress &>/dev/null
    tc qdisc del dev $port4 ingress &>/dev/null
    tc qdisc add dev $port2 ingress
    tc qdisc add dev $port4 ingress
    ip netns del red &> /dev/null
    ip netns del blue &> /dev/null
    ip addr flush dev $port2
    ip addr flush dev $port4
}
trap cleanup EXIT

function tc_filter() {
    eval2 tc filter $@
}

cleanup

title "Test TC chains"

echo "setup netns"
ip netns add red
ip netns add blue
ip link set $port1 netns red
ip link set $port3 netns blue
ip netns exec red ifconfig $port1 mtu 1400 up
ip netns exec blue ifconfig $port3 mtu 1400 up
ip netns exec red ip addr add 1.1.1.1/16 dev $port1
ip netns exec red ip addr add 1.1.1.2/16 dev $port1
ip netns exec red ip addr add 1.1.1.3/16 dev $port1
ip netns exec red ip addr add 1.1.1.4/16 dev $port1
ip netns exec red ip addr add 1.1.1.5/16 dev $port1
ip netns exec red ip addr add 1.1.2.0/16 dev $port1
ip netns exec blue ip addr add 1.1.1.6/16 dev $port3
ip netns exec blue ip addr add 1.1.1.7/16 dev $port3
ip netns exec blue ip addr add 1.1.1.8/16 dev $port3
ip netns exec blue ip addr add 1.1.1.9/16 dev $port3
ip netns exec blue ip addr add 1.1.1.10/16 dev $port3
ip netns exec blue ip addr add 1.1.2.1/16 dev $port3
ifconfig $port2 up
ifconfig $port4 up

echo "clean devices"
reset_tc $port2
reset_tc $port4

dst_mac=`ip netns exec blue ip link show $VF2 | grep ether | awk '{print $2}'`

start_check_syndrome

echo "adding hw only rules"
#pass '* -> 7-8' or '1-2 -> *'
tc_filter add dev $port2 ingress protocol ip prio 1 chain 0 flower skip_sw dst_mac $dst_mac dst_ip 1.1.1.8 action goto chain 1024
# if first fails we probably dont support chains offload
fail_if_err "TC chains offload is not supported"
tc_filter add dev $port2 ingress protocol ip prio 1 chain 0 flower skip_sw dst_mac $dst_mac dst_ip 1.1.1.7 action goto chain 1024
tc_filter add dev $port2 ingress protocol ip prio 1 chain 0 flower skip_sw dst_mac $dst_mac src_ip 1.1.1.1 action goto chain 1024
tc_filter add dev $port2 ingress protocol ip prio 1 chain 0 flower skip_sw dst_mac $dst_mac src_ip 1.1.1.2 action goto chain 1024
#pass '3 -> 6'
tc_filter add dev $port2 ingress protocol ip prio 2000 chain 0 flower skip_sw dst_mac $dst_mac src_ip 1.1.1.3 dst_ip 1.1.1.6 action goto chain 1024
#drop otherwise
tc_filter add dev $port2 ingress protocol ip prio 3000 chain 0 flower skip_sw dst_mac $dst_mac dst_ip 1.1.1.0/24 action drop

#fwd if passed the filter
tc_filter add dev $port2 ingress protocol ip prio 1 chain 1024 flower skip_sw dst_mac $dst_mac src_ip 1.1.1.0/24 action mirred egress redirect dev $port4

#trap for testing slow path on second chain
tc_filter add dev $port2 ingress protocol ip prio 1 chain 1025 flower skip_sw dst_mac $dst_mac action mirred egress redirect dev $port4

echo "adding sw only rules"
#arp and reverse traffic (skip_hw)
tc_filter add dev $port4 ingress protocol ip  prio 5000 flower skip_hw action mirred egress redirect dev $port2
tc_filter add dev $port2 ingress protocol arp prio 4000 flower skip_hw action mirred egress redirect dev $port4
tc_filter add dev $port4 ingress protocol arp prio 4000 flower skip_hw action mirred egress redirect dev $port2

# fail test if we couldn't add all rules
fail_if_err

#capture slow packets
timeout 5 tcpdump -c 2 -nei $port2 'icmp[icmptype] == 8 and (src 1.1.1.3 or dst 1.1.1.8)' &
sleep 0.5
tdpid=$!

# generate traffic
ip netns exec red timeout 0.25 ping -I 1.1.1.3 -i 0.25 -W 0.25 -c 1 1.1.1.8 || err "ping failed"
ip netns exec red timeout 0.25 ping -I 1.1.1.3 -i 0.25 -W 0.25 -c 1 1.1.1.7 || err "ping failed"
ip netns exec red timeout 0.25 ping -I 1.1.1.1 -i 0.25 -W 0.25 -c 1 1.1.1.6 || err "ping failed"
ip netns exec red timeout 0.25 ping -I 1.1.1.2 -i 0.25 -W 0.25 -c 1 1.1.1.6 || err "ping failed"

ip netns exec red timeout 0.25 ping -I 1.1.1.3 -i 0.25 -W 0.25 -c 1 1.1.1.6 || err "ping failed"

#drops
ip netns exec red timeout 0.25 ping -I 1.1.1.3 -i 0.25 -W 0.25 -c 1 1.1.1.9 && err "expected to fail ping"
ip netns exec red timeout 0.25 ping -I 1.1.1.4 -i 0.25 -W 0.25 -c 1 1.1.1.9 && err "expected to fail ping"
ip netns exec red timeout 0.25 ping -I 1.1.1.5 -i 0.25 -W 0.25 -c 1 1.1.1.9 && err "expected to fail ping"

#slow path
ip netns exec red timeout 0.25 ping -I 1.1.1.3 -i 0.25 -W 0.25 -c 1 1.1.2.1 && err "expected to get to slow path - first chain"
ip netns exec red timeout 0.25 ping -I 1.1.2.0 -i 0.25 -W 0.25 -c 1 1.1.1.8 && err "expected to get to slow path - second chain"

echo "check for two slow path packets"
wait $tdpid
[[ $? -eq 0 ]] && success || err "expected two slow path packet"

echo "checking offload stats"
sleep 3
stats=`sudo tc -s filter show dev $REP ingress proto ip | grep "Sent [0-9]* bytes" | awk '{ print $4 };' | xargs echo`
expected="2 1 1 1 1 3 5 0"
echo "got stats: $stats (expected: $expected)"
[[ "$stats" == "$expected" ]] && success || err "expected different packet stats, expected ($expected) but got ($stats)"

cleanup
check_syndrome || err
test_done
