#!/bin/bash


P1="ens2f0"
P2="ens2f1"

modprobe -r mlx5_ib mlx5_core
modprobe -r openvswitch
sleep 1

modprobe -v openvswitch
sleep 1
modprobe -v mlx5_core
sleep 1

vms=`virsh list | grep run | awk '{print $1}'`
for i in $vms; do virsh destroy $i ; done


echo 0 > /sys/class/net/$P1/device/sriov_numvfs
echo 0 > /sys/class/net/$P2/device/sriov_numvfs
sleep 2
echo 2 > /sys/class/net/$P1/device/sriov_numvfs
echo 2 > /sys/class/net/$P2/device/sriov_numvfs
sleep 1


ip link set $P1 vf 0 mac e4:1d:2d:fa:60:8a
ip link set $P1 vf 1 mac e4:1d:2d:fb:60:8b
ip link set $P2 vf 0 mac e4:1d:2d:11:80:8c
ip link set $P2 vf 1 mac e4:1d:2d:11:80:8d

echo 0000:81:00.2 > /sys/bus/pci/drivers/mlx5_core/unbind
echo 0000:81:00.3 > /sys/bus/pci/drivers/mlx5_core/unbind
echo 0000:81:02.2 > /sys/bus/pci/drivers/mlx5_core/unbind
echo 0000:81:02.3 > /sys/bus/pci/drivers/mlx5_core/unbind

devlink dev eswitch set pci/0000:81:00.0 mode switchdev
devlink dev eswitch set pci/0000:81:00.1 mode switchdev

echo 0000:81:00.2 > /sys/bus/pci/drivers/mlx5_core/bind
echo 0000:81:00.3 > /sys/bus/pci/drivers/mlx5_core/bind
echo 0000:81:02.2 > /sys/bus/pci/drivers/mlx5_core/bind
echo 0000:81:02.3 > /sys/bus/pci/drivers/mlx5_core/bind

ip link show $P1
ip link show $P2

