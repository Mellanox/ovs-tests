#!/bin/bash

NIC=ens2f0
VF=ens2f2
REP=ens2f0_0

IP=1.1.1.139

LOCAL_IP=7.7.7.10
REMOTE_IP=7.7.7.11

SRC_MAC="e4:11:22:4a:f4:50"
DST_MAC="5e:da:db:d4:a5:dd"


ifconfig $NIC $LOCAL_IP up
ip l del vxlan42 2>/dev/null
ip link add name vxlan42 type vxlan id 42 dev $NIC  remote $REMOTE_IP dstport 4789
sleep 1
#ifconfig vxlan42 $IP/24 up
ifconfig vxlan42 up

tc qdisc del dev vxlan42 ingress 2>/dev/null
tc qdisc del dev $REP ingress 2>/dev/null
tc qdisc add dev vxlan42 ingress
tc qdisc add dev $REP ingress

ip netns del ns0 2>/dev/null
ip netns add ns0
ip link set $VF netns ns0
ip netns exec ns0 ifconfig $VF $IP/24 up

# encap rules for packets from local to remote
tc filter add dev $REP protocol ip ingress flower  src_mac $SRC_MAC dst_mac $DST_MAC action tunnel_key set src_ip $LOCAL_IP dst_ip $REMOTE_IP dst_port 4789 id 42 action mirred egress redirect dev vxlan42
tc filter add dev $REP protocol arp ingress flower skip_hw action mirred egress redirect dev vxlan42

# decap rules for packets from remote to local
tc filter add dev vxlan42 protocol ip ingress flower src_mac $DST_MAC dst_mac $SRC_MAC enc_src_ip $REMOTE_IP enc_dst_ip $LOCAL_IP enc_key_id 42 enc_dst_port 4789 action tunnel_key unset action mirred egress redirect dev $REP
tc filter add dev vxlan42 protocol arp ingress flower skip_hw action mirred egress redirect dev $REP


ip netns exec ns0 ping -c 5 -w 1 -W 1 -i 0.1 1.1.1.138
