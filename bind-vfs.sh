#!/bin/bash

nic=${1:-ens5f0}

for i in `ls -1d  /sys/class/net/$nic/device/virtfn*`; do
    pci=$(basename `readlink $i`)
    echo "bind $pci"
    echo $pci > /sys/bus/pci/drivers/mlx5_core/bind
done
