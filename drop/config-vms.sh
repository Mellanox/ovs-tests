#!/bin/sh


uplinkp="10.212.224."
prefix="1.1.1."
subnet=24
vms=`seq 5 6`
nic="ens6"

set -e

for i in $vms ; do
	uplink="$uplinkp$i"
	ip="$prefix$i"	
        echo "test $uplink"
	ping -q -w1 $uplink >/dev/null
	echo "# $uplink - $ip/$subnet"
	ssh $uplink ifconfig $nic $ip/$subnet up
done
