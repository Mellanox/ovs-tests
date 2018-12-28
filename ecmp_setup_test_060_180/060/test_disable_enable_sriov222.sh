#!/bin/bash

NIC=ens1f0_0
SLEEP=12

tc qdisc add dev $NIC ingress

function add_rules() {

	tc filter add dev $NIC parent ffff: protocol ip pref 3 handle 0x1 flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 ip_proto udp src_port 11636 action mirred egress redirect dev $NIC
	tc filter add dev $NIC parent ffff: protocol ip pref 4 handle 0x1 flower dst_mac e4:1d:2d:5d:25:35 src_mac e4:1d:2d:5d:25:34 ip_proto udp src_port 2229 action mirred egress redirect dev $NIC

}

function test1() {
	echo "port1 down"
	ifconfig ens1f0 down
	echo 2 > /sys/class/net/ens1f0/device/sriov_numvfs
	echo "sleep $SLEEP"
	sleep $SLEEP

	echo "restore"
	ifconfig ens1f0 up
	echo 0 > /sys/class/net/ens1f0/device/sriov_numvfs
	echo "sleep $SLEEP"
	sleep $SLEEP

	echo "port2 down"
	ifconfig ens1f1 down
	echo 1 > /sys/class/net/ens1f0/device/sriov_numvfs
	echo "sleep $SLEEP"
	sleep $SLEEP

	echo "restore"
	ifconfig ens1f1 up
	echo 0 > /sys/class/net/ens1f0/device/sriov_numvfs
	echo "sleep $SLEEP"
	sleep $SLEEP
}


add_rules
for i in `seq 10`; do
	test1
done
