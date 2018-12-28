#!/bin/bash

HOST1="reg-r-vrt-020-001"
HOST2="reg-r-vrt-020-120"
SLEEP=12


function cmd_on() {
	local host=$1
	shift
	local cmd=$@
	echo "[$host] $cmd"
	ssh $host -C "$cmd"
}


function test1() {
	echo "port1 down"
	cmd_on $HOST1 ifconfig ens1f0 down
	cmd_on $HOST1 ifconfig ens1f0 down
	cmd_on $HOST1 "echo 2 > /sys/class/net/ens1f0/device/sriov_numvfs"
	cmd_on $HOST2 "echo 2 > /sys/class/net/ens1f0/device/sriov_numvfs"
	echo "sleep $SLEEP"
	sleep $SLEEP

	echo "restore"
	cmd_on $HOST1 ifconfig ens1f0 up
	cmd_on $HOST1 ifconfig ens1f0 up
	cmd_on $HOST1 "echo 0 > /sys/class/net/ens1f0/device/sriov_numvfs"
	cmd_on $HOST2 "echo 0 > /sys/class/net/ens1f0/device/sriov_numvfs"
	echo "sleep $SLEEP"
	sleep $SLEEP

	echo "port2 down"
	cmd_on $HOST1 ifconfig ens1f1 down
	cmd_on $HOST1 ifconfig ens1f1 down
	cmd_on $HOST1 "echo 1 > /sys/class/net/ens1f0/device/sriov_numvfs"
	cmd_on $HOST2 "echo 1 > /sys/class/net/ens1f0/device/sriov_numvfs"
	echo "sleep $SLEEP"
	sleep $SLEEP

	echo "restore"
	cmd_on $HOST1 ifconfig ens1f1 up
	cmd_on $HOST1 ifconfig ens1f1 up
	cmd_on $HOST1 "echo 0 > /sys/class/net/ens1f0/device/sriov_numvfs"
	cmd_on $HOST2 "echo 0 > /sys/class/net/ens1f0/device/sriov_numvfs"
	echo "sleep $SLEEP"
	sleep $SLEEP
}


for i in `seq 10`; do
	test1
done
