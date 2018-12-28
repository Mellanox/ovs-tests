#!/bin/bash

cat <<EOF

	int0 18.18.18.60
	int1 19.19.19.60
      +----------+
    P1|  HOST2   |P2
   +--+          +--+
   |  +----------+  |
   |                |
P1 |             P1 |
+--+---+        +---+--+
|      |        |      |
|  R1  |        |  R2  |
|      |        |      |
+-+----+        +----+-+
  | P2               | P2
  |                  |
  |                  |
  |   +----------+   |
  +---+  HOST1   +---+ VF1 18.18.18.120
    P2|          |P1
      +----------+
VF2 19.19.19.120

EOF
sleep 1

HOST1="reg-r-vrt-020-120"
HOST1_P1="ens2f0"
HOST1_P2="ens2f1"

R1="reg-r-vrt-020-001"
R1_P1="ens1f0"
R1_P2="ens1f1"

R2="reg-r-vrt-020-180"
R2_P1="ens1f0"
R2_P2="ens1f1"

HOST2="reg-r-vrt-020-060"
HOST2_P1="ens1f0"
HOST2_P2="ens1f1"

HOST1_TUN="6.0.10.120"
HOST1_P1_IP="7.1.10.120"
HOST1_P2_IP="7.2.10.120"

HOST2_TUN="9.0.10.60"
HOST2_P1_IP="8.2.10.60"
HOST2_P2_IP="8.1.10.60"

R1_P1_IP="8.2.10.1"
R1_P2_IP="7.2.10.1"

R2_P1_IP="8.1.10.1"
R2_P2_IP="7.1.10.1"


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
cmd_on $HOST1 "ip r a $HOST2_TUN_NET nexthop via $R2_P2_IP dev $HOST1_P1 weight 1 nexthop via $R1_P2_IP dev $HOST1_P2 weight 1"
cmd_on $HOST1 "ovs-vsctl add-br br-vxlan"
cmd_on $HOST1 "ovs-vsctl add-port br-vxlan vxlan40 -- set interface vxlan40 type=vxlan options:remote_ip=$HOST2_TUN options:local_ip=$HOST1_TUN options:key=40 options:dst_port=4789"
cmd_on $HOST1 "ovs-vsctl add-port br-vxlan int0 -- set interface int0 type=internal"
cmd_on $HOST1 "ifconfig int0 18.18.18.120/24 up"
cmd_on $HOST1 "sysctl -w net.ipv4.fib_multipath_hash_policy=1"

echo "config $HOST2"
cmd_on $HOST2 $clean_ovs
cmd_on $HOST2 $clean_vxlan
cmd_on $HOST2 "ovs-vsctl add-br ov1 ; ifconfig ov1 $HOST2_TUN/24 up"
cmd_on $HOST2 "ifconfig $HOST2_P1 $HOST2_P1_IP/24 up ; ifconfig $HOST2_P2 $HOST2_P2_IP/24 up"
cmd_on $HOST2 "ip r d $HOST1_TUN_NET"
cmd_on $HOST2 "ip r a $HOST1_TUN_NET nexthop via $R1_P1_IP dev $HOST2_P1 weight 256 nexthop via $R2_P1_IP dev $HOST2_P2 weight 1"
cmd_on $HOST2 "ovs-vsctl add-br br-vxlan"
cmd_on $HOST2 "ovs-vsctl add-port br-vxlan vxlan40 -- set interface vxlan40 type=vxlan options:remote_ip=$HOST1_TUN options:local_ip=$HOST2_TUN options:key=40 options:dst_port=4789"
cmd_on $HOST2 "ovs-vsctl add-port br-vxlan int0 -- set interface int0 type=internal"
cmd_on $HOST2 "ifconfig int0 18.18.18.60/24 up"
cmd_on $HOST2 "ovs-vsctl add-port br-vxlan int1 -- set interface int1 type=internal"
cmd_on $HOST2 "ifconfig int1 19.19.19.60/24 up"
cmd_on $HOST2 "sysctl -w net.ipv4.fib_multipath_hash_policy=1"

echo "config $R1"
cmd_on $R1 "ifconfig $R1_P1 $R1_P1_IP/24 up ; ifconfig $R1_P2 $R1_P2_IP/24 up"
cmd_on $R1 "ip r d $HOST1_TUN_NET ; ip r d $HOST2_TUN_NET"
cmd_on $R1 "ip r a $HOST1_TUN_NET via $HOST1_P2_IP dev $R1_P2"
cmd_on $R1 "ip r a $HOST2_TUN_NET via $HOST2_P1_IP dev $R1_P1"

echo "config $R2"
cmd_on $R2 "ifconfig $R2_P1 $R2_P1_IP/24 up ; ifconfig $R2_P2 $R2_P2_IP/24 up"
cmd_on $R2 "ip r d $HOST1_TUN_NET ; ip r d $HOST2_TUN_NET"
cmd_on $R2 "ip r a $HOST1_TUN_NET via $HOST1_P1_IP dev $R2_P2"
cmd_on $R2 "ip r a $HOST2_TUN_NET via $HOST2_P2_IP dev $R2_P1"
