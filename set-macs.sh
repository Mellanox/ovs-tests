#!/bin/bash

nic=${1:?param 1 interface}
num_vfs=$2 # optional

echo nic $nic
if [ ! -e /sys/class/net/$nic ]; then
    exit 1
fi

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

echo "Set mac on $nic vfs mac"
max_vf=`ls -1d /sys/class/net/ens1f0/device/virtfn* | wc -l`
let max_vf-=1
for vf in `seq 0 $max_vf`; do
    ip link set $nic vf $vf mac $mac_prefix$mac_vf
    ((mac_vf=mac_vf+1))
done

# rebind interfaces
echo "rebind vfs on $nic"
for i in `ls -1d  /sys/class/net/$nic/device/virtfn*`; do
    pci=$(basename `readlink $i`)
    echo $pci > /sys/bus/pci/drivers/mlx5_core/unbind 2>/dev/null
    echo $pci > /sys/bus/pci/drivers/mlx5_core/bind
done
