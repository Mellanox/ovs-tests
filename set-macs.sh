#!/bin/bash

nic=${1:?param 1 interface}
num_vfs=$2 # optional

echo nic $nic
set -e
ip link show $nic >/dev/null
set +e

sriov_numvfs="/sys/class/net/$nic/device/sriov_numvfs"
if [ "$num_vfs" == "" ]; then
    num_vfs=`cat $sriov_numvfs`
fi
echo num_vfs $num_vfs
echo "Set $num_vfs vfs on $nic"
echo $num_vfs > $sriov_numvfs

if [ "$num_vfs" == "0" ]; then
    exit
fi

hw=`cat /sys/class/net/$nic/address`
f1=`echo $hw | cut -d: -f1`
f2=`echo $hw | cut -d: -f2`
f3=`echo $hw | cut -d: -f3`
f4=`echo $hw | cut -d: -f4`
f5=`echo $hw | cut -d: -f5`
f6=`echo $hw | cut -d: -f6`

mac_prefix="e4:11:22:$f5:$f6:"
mac_vf=50

for vf in `ip link show $nic | grep "vf " | awk {'print $2'}`; do
    echo "Set $nic vf $vf mac $mac_prefix$mac_vf"
    ip link set $nic vf $vf mac $mac_prefix$mac_vf
    ((mac_vf=mac_vf+1))
done

ip link show $nic

# rebind interfaces
for i in `ls -1d  /sys/class/net/$nic/device/virtfn*`; do
    pci=$(basename `readlink $i`)
    echo "rebind $pci"
    echo $pci > /sys/bus/pci/drivers/mlx5_core/unbind 2>/dev/null
    echo $pci > /sys/bus/pci/drivers/mlx5_core/bind
done
