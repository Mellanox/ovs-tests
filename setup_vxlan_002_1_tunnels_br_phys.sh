#!/bin/bash

DEV="ens5f0"

systemctl start openvswitch
sleep 2
ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br

OVS1="vx42"
OVS2="vx44"
OVS3="vx46"

LOCAL_IP=70.70.70.1
REMOTE_IP=70.70.70.2

for i in $DEV ${DEV}_0; do
    ip link set dev $i down
    ip addr flush dev $i
    ip link set dev $i up
done

function create_br_pys() {
    ovs-vsctl add-br br-pys
    ifconfig br-pys $LOCAL_IP/24 up
    ovs-vsctl add-port br-pys ${DEV}
    ip link show br-pys
}

create_br_pys
#ifconfig $DEV $LOCAL_IP/24 up

function create_br_int42() {
    ovs-vsctl add-br br-int42
    ovs-vsctl add-port br-int42 ${DEV}_0 

    ovs-vsctl add-br br-tun42
    ovs-vsctl add-port br-tun42 vxlan42 -- set interface vxlan42 type=vxlan options:remote_ip=$REMOTE_IP options:key=42 options:dst_port=4789

    ovs-vsctl add-port br-int42 patch0 -- set interface patch0 type=patch options:peer=patch1
    ovs-vsctl add-port br-tun42 patch1 -- set interface patch1 type=patch options:peer=patch0
}

function create_single_br() {
    ovs-vsctl add-br br-tun42
    ovs-vsctl add-port br-tun42 ${DEV}_0 
    ovs-vsctl add-port br-tun42 vxlan42 -- set interface vxlan42 type=vxlan options:remote_ip=$REMOTE_IP options:key=42 options:dst_port=4789
}

#create_br_int42
create_single_br

# show
ovs-vsctl show
ovs-dpctl show
ovs-vsctl get Open_vSwitch . other_config
