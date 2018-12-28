#!/bin/bash

## we want to have this route for packets but without changing them
## e.g the source/dest mac addresses remain untouched

## wire --> PF0 --> OVS-1 --> PF0.VF0 --> DPDK --> PF1.VF0 --> OVS-2 --> PF1 --> wire

## we want OVS to be in learning mode, for that end, need to make sure that they only OF rule
## is the normal one, see it with this command

## ovs-ofctl dump-flows ${OVS}


## packet (X --> Y) --> PF0 --> OVS-1 --> PF0.VF0

## packet (Y --> X) --> PF1.V0 --> DPDK --> PF0.V0  --> OVS-1

## packet (X --> Y) --> PF0.V0 --> DPDK --> PF1.V0  --> OVS-2
 
## packet (Y --> X) --> PF1 --> OVS-2 --> PF1.VF0


PF1=enp8s0f0
PF2=enp8s0f1
OVS_PF1=ovs-sriov-1
OVS_PF2=ovs-sriov-2

## RHEL
#OVS_SERVICE=/etc/init.d/openvswitch

## Ubuntu
OVS_SERVICE=/etc/init.d/openvswitch-switch

#IDLE=3000000
IDLE=10000

mount -t debugfs none /sys/kernel/debug

#echo 'file net/switchdev/switchdev.c +p' > /sys/kernel/debug/dynamic_debug/control
#echo 'file drivers/net/ethernet/mellanox/mlx5/core/en_rep.c +p' > /sys/kernel/debug/dynamic_debug/control
#echo 'file drivers/net/ethernet/mellanox/mlx5/core/en_flow_offloads.c +p' > /sys/kernel/debug/dynamic_debug/control

ifconfig ${PF1} 0
ifconfig ${PF2} 0

ifconfig ${PF1} up
ifconfig ${PF2} up

echo "0000:08:00.2" > /sys/bus/pci/drivers/mlx5_core/unbind 
echo "0000:08:00.6" > /sys/bus/pci/drivers/mlx5_core/unbind 

devlink dev eswitch set pci/0000:08:00.0 mode switchdev
devlink dev eswitch set pci/0000:08:00.1 mode switchdev
devlink dev eswitch set pci/0000:05:00.0 inline-mode transport
devlink dev eswitch set pci/0000:08:00.1 inline-mode transport
#ethtool --set-priv-flags ${PF1} vfs_representors on
#ethtool --set-priv-flags ${PF2} vfs_representors on

sleep 1 

ifconfig ${PF1}_0 up
#ifconfig ${PF1}_1 up

ifconfig ${PF2}_0 up
#ifconfig ${PF2}_1 up

ethtool -K $PF1 hw-tc-offload on
ethtool -K $PF2 hw-tc-offload on
ethtool -K ${PF1}_0 hw-tc-offload on
ethtool -K ${PF2}_0 hw-tc-offload on

systemctl restart openvswitch

sleep 3

ovs-vsctl set Open_vSwitch . other_config:hw-offload=true

ovs-vsctl del-br $OVS_PF1
ovs-vsctl del-br $OVS_PF2

# add new OVS instance
ovs-vsctl add-br $OVS_PF1

ovs-vsctl add-br $OVS_PF2

ovs-vsctl set Open_vSwitch . other_config:skip-hw=false
ovs-vsctl set Open_vSwitch . other_config:max-idle=$IDLE
ovs-appctl upcall/set-flow-limit 200000

# if using VXLAN
# 1.1.1.43 --> 1.1.1.44 (IXIA TX --> PF1 RX)
# either put PF1 in promisc mode or better have DMAC= PF1 MAC
# ip link show ${PF1} | grep ether
ip addr add dev ${PF1} 1.1.1.44/24
arp -s 1.1.1.43 e4:11:22:33:44:90
ovs-vsctl add-port $OVS_PF1 vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=1.1.1.44 options:remote_ip=1.1.1.43 options:key=98

# 2.2.2.44 --> 2.2.2.43 (PF2 TX --> IXIA RX)
# need static ARP for IXIA on PF2 (arp set ...)
ip addr add dev ${PF2} 2.2.2.44/24
arp -s 2.2.2.43 e4:11:22:33:44:80


ovs-vsctl add-port $OVS_PF2 vxlan2 -- set interface vxlan2 type=vxlan options:local_ip=2.2.2.44 options:remote_ip=2.2.2.43 options:key=98

ovs-vsctl add-port $OVS_PF1 ${PF1}_0

ovs-vsctl add-port $OVS_PF2 ${PF2}_0

tc qdisc add dev vxlan_sys_4789 ingress

sleep 1

ovs-vsctl show

ovs-dpctl show

ovs-dpctl dump-flows
