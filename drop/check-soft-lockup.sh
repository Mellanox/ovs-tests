#!/bin/bash

NIC=ens5f0
PCI=$(basename `readlink /sys/class/net/$NIC/device`)
hv=`hostname -s`

sh load.sh
/labhome/roid/scripts/ovs/unbind-vfs.sh $NIC
set -e
devlink dev eswitch set pci/$PCI inline-mode transport
devlink dev eswitch show pci/$PCI
vms=`seq 5 6` ;    for i in $vms; do virsh -q start ${hv}-00${i}-Fedora-24 ; done
service openvswitch restart
set +e
sh config-br.sh

_t1=`date +"%s"`

START=2000
COUNT=4000
((END=START+COUNT))
sh drop.sh $START $END

_t2=`date +"%s"`
(( _t=40-(t1-t2) ))
sleep $_t
set -e
sh config-vms.sh

# TEST with/without cls_flower pre-loaded
modprobe -v cls_flower
#modprobe -rv cls_flower

sleep 0.5
set +e

VM1="10.212.224.5"
TARGET="1.1.1.6"
RUNTIME=30
echo "Start traffic from $VM1"
ssh $VM1 timeout $RUNTIME ./noodle -c $TARGET -b 100 -r 10 -l $START -p 9999 -C $COUNT -n 5000 &
NOODLE_PID=$!
sleep 4
ovs-dpctl dump-flows hw_netlink@ovs-hw_netlink > /tmp/1.1
ovs-dpctl dump-flows hw_netlink@ovs-hw_netlink > /tmp/1.1
sleep 2
kill $NOODLE_PID
sleep 2
echo "Done"
