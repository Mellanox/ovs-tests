#!/bin/bash

cat <<EOF
	
	int0 18.18.18.60
	int1 19.19.19.60

           +-----------------+
           |     HOST2       |
           |      020-060    |
           |       P1        |
           +-------+---------+
                   |
                   |
+------------------+------------------------+
|                  13                       |
|                                           |
|                                           |
|           14                 15           |
+-----------+------------------+------------+
            |                  |
            |                  |
            |                  |
            |                  |
            |                  |
         +--+------------------+--+
         |  P1                P2  |    VF1 18.18.18.180
         |        HOST1           |    VF2(P2) 19.19.19.180
         |       020-180          |
         |                        |
         +------------------------+


EOF
sleep 1

HOST1="reg-r-vrt-020-180"
HOST1_P1="ens2f0"
HOST1_P2="ens2f1"

HOST2="reg-r-vrt-020-060"
HOST2_P1="ens1f0"

PORT14_IP="37.2.10.1"
PORT15_IP="37.1.10.1"
PORT13_IP="38.2.10.1"

HOST1_TUN="36.0.10.180"
HOST1_P1_IP="37.2.10.180"
HOST1_P2_IP="37.1.10.180"

HOST2_TUN="39.0.10.60"
HOST2_P1_IP="38.2.10.60"

function getnet() {
	echo `ipcalc -n $1 | cut -d= -f2`/24
}

function cmd_on() {
	local host=$1
	shift
	local cmd=$@
	echo "[$host] $cmd"
	ssh $host -C "$cmd"
}


HOST1_TUN_NET=`getnet $HOST1_TUN/24`
HOST2_TUN_NET=`getnet $HOST2_TUN/24`

clean_ovs="service openvswitch restart ; ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br"
clean_vxlan="ip -br l show type vxlan | cut -d' ' -f1 | xargs -I {} ip l del {} 2>/dev/null"

echo "config $HOST1"
cmd_on $HOST1 $clean_ovs
cmd_on $HOST1 $clean_vxlan
cmd_on $HOST1 "ovs-vsctl add-br ov1 ; ifconfig ov1 $HOST1_TUN/24 up"
cmd_on $HOST1 "ifconfig $HOST1_P1 $HOST1_P1_IP/24 up ; ifconfig $HOST1_P2 $HOST1_P2_IP/24 up"
cmd_on $HOST1 "ip r d $HOST2_TUN_NET"
cmd_on $HOST1 "ip r a $HOST2_TUN_NET nexthop via $PORT14_IP dev $HOST1_P1 weight 1 nexthop via $PORT15_IP dev $HOST1_P2 weight 1"
cmd_on $HOST1 "ovs-vsctl add-br br-vxlan"
cmd_on $HOST1 "ovs-vsctl add-port br-vxlan vxlan40 -- set interface vxlan40 type=vxlan options:remote_ip=$HOST2_TUN options:local_ip=$HOST1_TUN options:key=40 options:dst_port=4789"
cmd_on $HOST1 "ovs-vsctl add-port br-vxlan int0 -- set interface int0 type=internal"
cmd_on $HOST1 "ifconfig int0 18.18.18.180/24 up"
cmd_on $HOST1 "sysctl -w net.ipv4.fib_multipath_hash_policy=1"

echo "config $HOST2"
cmd_on $HOST2 $clean_ovs
cmd_on $HOST2 $clean_vxlan
cmd_on $HOST2 "ovs-vsctl add-br ov1 ; ifconfig ov1 $HOST2_TUN/24 up"
cmd_on $HOST2 "ifconfig $HOST2_P1 $HOST2_P1_IP/24 up"
cmd_on $HOST2 "ip r d $HOST1_TUN_NET"
cmd_on $HOST2 "ip r a $HOST1_TUN_NET via $PORT13_IP dev $HOST2_P1"
cmd_on $HOST2 "ovs-vsctl add-br br-vxlan"
cmd_on $HOST2 "ovs-vsctl add-port br-vxlan vxlan40 -- set interface vxlan40 type=vxlan options:remote_ip=$HOST1_TUN options:local_ip=$HOST2_TUN options:key=40 options:dst_port=4789"
cmd_on $HOST2 "ovs-vsctl add-port br-vxlan int0 -- set interface int0 type=internal"
cmd_on $HOST2 "ifconfig int0 18.18.18.60/24 up"
cmd_on $HOST2 "ovs-vsctl add-port br-vxlan int1 -- set interface int1 type=internal"
cmd_on $HOST2 "ifconfig int1 19.19.19.60/24 up"

