#!/bin/bash

#service openvswitch restart
#sleep 2
#ip l | grep vxlan_sys_1478
#ip l | grep zzz

ovs-vsctl -- add-br ovs-sriov
ovs-vsctl show

# ovs will recreate the interface. we can notice the ifindex number changes.
ovs-vsctl add-port ovs-sriov vxlan0 -- set interface vxlan0 type=vxlan options:local_ip=13.22.248.1 options:remote_ip=11.22.139.1 options:key=5 options:dst_port=1478

ip link add dev zzz type dummy
ovs-vsctl add-port ovs-sriov zzz
ovs-vsctl show

ovs-vsctl del-br ovs-sriov
sleep 5

# ovs doesn't del the interfaces when deleting the bridge.
ip l | grep vxlan_sys_1478
ip l | grep zzz

ip link del dev vxlan_sys_1478
ip link del dev zzz
