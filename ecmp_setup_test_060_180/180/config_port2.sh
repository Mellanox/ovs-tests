#!/bin/bash

echo "config sriov on peer pf"
echo 2 > /sys/class/net/ens2f1/device/sriov_numvfs
sleep 1
~roid/scripts/ovs/set-macs.sh ens2f1
~roid/scripts/ovs/unbind-vfs.sh ens2f1
sleep 1
devlink dev eswitch set pci/0000:81:00.1 mode switchdev inline-mode transport

echo "config ovs"
ifconfig int0 0 2>/dev/null
ovs-vsctl del-port br-vxlan int0 2>/dev/null
~roid/scripts/ovs/bind-vfs.sh ens2f0
ifconfig ens2f2 18.18.18.120/24 up

~roid/scripts/ovs/bind-vfs.sh ens2f1
ifconfig enp129s1f2 19.19.19.120/24 up
ifconfig ens2f1_0 up

echo "add ports to ovs bridge"
ovs-vsctl add-port br-vxlan ens2f0_0
ovs-vsctl add-port br-vxlan ens2f1_0

function add_static_arp() {
	echo "add static arps for now"
	ip n d 7.1.10.1 lladdr 24:8a:07:a5:28:99 dev ens2f0
	ip n a 7.1.10.1 lladdr 24:8a:07:a5:28:99 dev ens2f0
	ip n d 7.2.10.1 lladdr 24:8a:07:a5:28:79 dev ens2f1
	ip n a 7.2.10.1 lladdr 24:8a:07:a5:28:79 dev ens2f1
}

#add_static_arp
