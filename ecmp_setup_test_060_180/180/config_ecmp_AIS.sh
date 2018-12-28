#!/bin/bash

cat <<EOF

      +------------------------------------+
      |                                    |
      |         Tunnel end point           |
      |         39.0.10.60                 |
      |                                    |
      | 38.1.10.60            38.2.10.60   |
      |   ens1f1                  ens1f0   |
      +----+-------------------------+-----+
           |                         |
           |                         |
           |                         |
+----------+-------------------------+---------------+
|        port14                     port13           |
|       38.1.10.1                 38.2.10.1          |
|                                                    |
|                                                    |
|                                                    |
|            r-sw-switch19                           |
|                                                    |
|                                                    |
|        37.1.10.1                 37.2.10.2         |
|          port15                  port16            |
+-----------+-------------------------+--------------+
            |                         |
            |                         |
            |                         |
         +--+-------------------------+-----+
         |  ens2f1                ens2f0    |
         |  37.1.10.180         37.2.10.180 |
         |                                  |
         |     Tunnel end point             |
         |     36.0.10.180                  |
         |                                  |
         +----------------------------------+


EOF
sleep 3

HOST180="reg-r-vrt-020-180"
HOST180_P1="ens2f0"
HOST180_P2="ens2f1"

HOST060="reg-r-vrt-020-060"
HOST060_P1="ens1f0"
HOST060_P2="ens1f1"

HOST180_TUN="36.0.10.180"
HOST180_P1_IP="37.2.10.180"
HOST180_P2_IP="37.1.10.180"

HOST060_TUN="39.0.10.60"
HOST060_P1_IP="38.2.10.60"
HOST060_P2_IP="38.1.10.60"

R12_IP="37.2.10.1"
R11_IP="37.1.10.1"
R7_IP="38.2.10.1"
R8_IP="38.1.10.1"

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


HOST180_TUN_NET=`getnet $HOST180_TUN/24`
HOST060_TUN_NET=`getnet $HOST060_TUN/24`

clean_ovs="service openvswitch restart ; ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br"
clean_vxlan="ip -br l show type vxlan | cut -d' ' -f1 | xargs -I {} ip l del {} 2>/dev/null"

echo "config $HOST180"
cmd_on $HOST180 $clean_ovs
cmd_on $HOST180 $clean_vxlan
cmd_on $HOST180 "ovs-vsctl add-br ov1 ; ifconfig ov1 $HOST180_TUN/24 up"
cmd_on $HOST180 "ifconfig $HOST180_P1 $HOST180_P1_IP/24 up ; ifconfig $HOST180_P2 $HOST180_P2_IP/24 up"
cmd_on $HOST180 "ip r d $HOST060_TUN_NET 2>/dev/null"
cmd_on $HOST180 "ip r a $HOST060_TUN_NET nexthop via $R12_IP dev $HOST180_P1 weight 1 nexthop via $R11_IP dev $HOST180_P2 weight 1"
cmd_on $HOST180 "ovs-vsctl add-br br-vxlan"
cmd_on $HOST180 "ovs-vsctl add-port br-vxlan vxlan40 -- set interface vxlan40 type=vxlan options:remote_ip=$HOST060_TUN options:local_ip=$HOST180_TUN options:key=40 options:dst_port=4789"
cmd_on $HOST180 "ovs-vsctl add-port br-vxlan ${HOST180_P1}_0"
cmd_on $HOST180 "ovs-vsctl add-port br-vxlan ${HOST180_P1}_1"
cmd_on $HOST180 "ovs-vsctl add-port br-vxlan ${HOST180_P2}_0"
cmd_on $HOST180 "ovs-vsctl add-port br-vxlan ${HOST180_P2}_1"


echo "config $HOST060"
cmd_on $HOST060 $clean_ovs
cmd_on $HOST060 $clean_vxlan
cmd_on $HOST060 "ovs-vsctl add-br ov1 ; ifconfig ov1 $HOST060_TUN/24 up"
cmd_on $HOST060 "ifconfig $HOST060_P1 $HOST060_P1_IP/24 up ; ifconfig $HOST060_P2 $HOST060_P2_IP/24 up"
cmd_on $HOST060 "ip r d $HOST180_TUN_NET 2>/dev/null"
cmd_on $HOST060 "ip r a $HOST180_TUN_NET nexthop via $R7_IP dev $HOST060_P1 weight 1 nexthop via $R8_IP dev $HOST060_P2 weight 1"
cmd_on $HOST060 "ovs-vsctl add-br br-vxlan"
cmd_on $HOST060 "ovs-vsctl add-port br-vxlan vxlan40 -- set interface vxlan40 type=vxlan options:remote_ip=$HOST180_TUN options:local_ip=$HOST060_TUN options:key=40 options:dst_port=4789"
cmd_on $HOST060 "ovs-vsctl add-port br-vxlan ${HOST060_P1}_0"
cmd_on $HOST060 "ovs-vsctl add-port br-vxlan ${HOST060_P1}_1"
cmd_on $HOST060 "ovs-vsctl add-port br-vxlan ${HOST060_P2}_0"
cmd_on $HOST060 "ovs-vsctl add-port br-vxlan ${HOST060_P2}_1"

