#!/bin/bash

#service openvswitch restart
#sleep 2

ovs-vsctl -- add-br ovs-sriov
ovs-vsctl show

ovs-vsctl add-port ovs-sriov vxlan0 -- set interface vxlan0 type=vxlan options:local_ip=13.22.248.1 options:remote_ip=11.22.139.1 options:key=5 options:dst_port=1478
ip link add dev zzz type dummy
ovs-vsctl add-port ovs-sriov zzz
ovs-vsctl show

ovs-vsctl del-br ovs-sriov
sleep 5
ip link del dev vxlan_sys_1478
ip link del dev zzz
