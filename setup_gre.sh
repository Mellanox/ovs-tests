#!/bin/bash

PF=ens1f0
VF=ens1f2
REP=ens1f0_0

LOCAL_IP=1.1.1.1
local_tun=7.7.7.10
remote_tun=7.7.7.11

REMOTE=dev-r-vrt-138
REMOTE_IP=1.1.1.2

#config remote
ssh $REMOTE "ip link del gre_sys"
ssh $REMOTE "ip link add name gre_sys type gretap dev ens1f0 remote $local_tun nocsum nokey"
ssh $REMOTE "ifconfig ens1f0 $remote_tun/24 up"
ssh $REMOTE "ifconfig gre_sys $REMOTE_IP/24 up"

# config local
service openvswitch restart
ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br
ovs-vsctl add-br ov1
ovs-vsctl add-port ov1 gre0 -- set interface gre0 type=gre options:local_ip=$local_tun options:remote_ip=$remote_tun
ovs-vsctl add-port ov1 $REP

ifconfig $PF $local_tun/24 up
ifconfig $VF $LOCAL_IP/24 up
