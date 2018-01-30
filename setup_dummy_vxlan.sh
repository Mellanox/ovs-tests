#!/bin/bash

NIC=ens1f0

IP=1.1.1.138

LOCAL_IP=7.7.7.11
REMOTE_IP=7.7.7.10

ifconfig $NIC $LOCAL_IP up

ip l del vxlan42
ip link add name vxlan42 type vxlan id 42 dev $NIC  remote $REMOTE_IP dstport 4789
ifconfig vxlan42 $IP/24 up

