#!/bin/sh

virsh start reg-r-vrt-020-060-061-Fedora-25
echo "wait for vm"
sleep 30

ssh root@reg-r-vrt-020-060-061 ifconfig ens6 18.18.18.61/24 up

