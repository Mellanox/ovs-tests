#!/bin/bash

nic1=ens1f0
vf=ens1f2
rep=ens1f0_0

IP=1.1.1.7
REMOTE=1.1.1.8

LOCAL_TUN=7.7.7.7
REMOTE_IP=7.7.7.8
VXLAN_ID=42

ifconfig $nic1 down
ifconfig $nic1 up


function test_nic() {
    local n=$1
    if [ ! -e /sys/class/net/$n ]; then
        echo "Cannot find $n"
        exit 1
    fi
}

ip netns del ns0 &>/dev/null
ip netns del ns1 &>/dev/null
sleep 0.5
systemctl stop openvswitch
#echo 0 > /sys/class/net/$nic1/device/sriov_numvfs
echo 2 > /sys/class/net/$nic1/device/sriov_numvfs
~roid/scripts/ovs/unbind-vfs.sh $nic1
~roid/scripts/ovs/devlink-mode.sh $nic1 switchdev
pci=0000:01:00.0
devlink dev eswitch set pci/$pci inline-mode transport
sleep 1
~roid/scripts/ovs/bind-vfs.sh $nic1
test_nic $nic1
test_nic $vf
test_nic $rep
sleep 1

for i in $nic1 $vf $rep ; do
	ifconfig $i down
	ifconfig $i up
done

echo "Restarting OVS"
systemctl restart openvswitch
sleep 0.5
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
ovs-vsctl remove Open_vSwitch . other_config tc-policy
ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br 2>/dev/null
systemctl restart openvswitch

nf_liberal="/proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal"
if [ -e $nf_liberal ]; then
    echo 1 > $nf_liberal
    echo "`basename $nf_liberal` set to: `cat $nf_liberal`"
else
    echo "Cannot find $nf_liberal"
fi

sleep 1

conntrack -F

tc qdisc add dev $nic1 ingress 2>/dev/null
ifconfig $nic1 $LOCAL_TUN/24 up
# XXX WA SimX bug? interface not receiving traffic from tap device to down&up to fix it.
ifconfig $nic1 down && ifconfig $nic1 up
ifconfig $rep down  && ifconfig $rep up

ovs-vsctl add-br br-ovs
ovs-vsctl add-port br-ovs $rep
#ip netns exec ns0 ip n r 1.1.1.2 dev ens1f2 lladdr 00:00:11:11:11:11
ovs-vsctl add-port br-ovs vxlan1 -- set interface vxlan1 type=vxlan options:local_ip=$LOCAL_TUN options:remote_ip=$REMOTE_IP options:key=$VXLAN_ID options:dst_port=4789

function add_openflow_rules() {
    ovs-ofctl del-flows br-ovs
    #ovs-ofctl add-flow br-ovs in_port=$nic1,dl_type=0x0806,actions=output:$rep
    ovs-ofctl add-flow br-ovs in_port=$rep,dl_type=0x0806,actions=output:vxlan1
    ovs-ofctl add-flow br-ovs in_port=vxlan1,dl_type=0x0806,actions=output:$rep
    ovs-ofctl add-flow br-ovs in_port=$rep,icmp,actions=output:vxlan1
    ovs-ofctl add-flow br-ovs in_port=vxlan1,icmp,actions=output:$rep
    ovs-ofctl add-flow br-ovs "table=0, udp,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, udp,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, udp,ct_state=+trk+est actions=normal"
    ovs-ofctl dump-flows br-ovs --color
}

add_openflow_rules

ip netns add ns0
ip link set dev $vf netns ns0
ip netns exec ns0 ifconfig $vf $IP/24 up

ip a show dev $nic1
ip netns exec ns0 ip a s dev $vf

# icmp
ip netns exec ns0 ping -q -c 1 -i 0.1 -w 1 $REMOTE
# udp
#ip netns exec ns1 nc -u -l &
#ip netns exec ns0 sh -c "echo aaaa | nc -u 1.1.1.2"
#ip netns exec ns1 iperf -u -s &
#ip netns exec ns0 iperf -u -c 1.1.1.2 -t 2

echo "dump-flows"
/labhome/roid/scripts/ovs-df.sh --names
conntrack -L
