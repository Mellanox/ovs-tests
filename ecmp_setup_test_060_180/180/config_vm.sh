#!/bin/sh

virsh start reg-r-vrt-020-180-201-Fedora-24
#virsh start reg-r-vrt-020-180-202-Fedora-24
echo "wait for vm"
sleep 30

ssh root@reg-r-vrt-020-180-201 ifconfig ens6 18.18.18.201/24 up
ssh root@reg-r-vrt-020-180-201 ifconfig ens6 mtu 1410

#ssh root@reg-r-vrt-020-180-202 ifconfig ens6 18.18.18.202/24 up
