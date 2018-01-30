#!/bin/bash

PF=ens2f0
REP=ens2f0_0

LOCAL_IP=7.7.7.11
REMOTE_IP=7.7.7.10

ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br
ovs-vsctl add-br ov1
ovs-vsctl add-port ov1 vxlan42 -- set interface vxlan42 type=vxlan options:remote_ip=$REMOTE_IP options:key=42 options:dst_port=4789
ovs-vsctl add-port ov1 $REP

ifconfig $PF $LOCAL_IP up
