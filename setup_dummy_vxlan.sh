#!/bin/bash

NIC=ens1f0

IP=1.1.1.8

LOCAL_TUN=7.7.7.8
REMOTE_TUN=7.7.7.7
VXLAN_ID=42

ifconfig $NIC $LOCAL_TUN/24 up

ip l del vxlan1 &>/dev/null
ip link add name vxlan1 type vxlan id $VXLAN_ID dev $NIC remote $REMOTE_TUN dstport 4789
ifconfig vxlan1 $IP/24 up

ip a show dev $NIC
ip a show dev vxlan1
