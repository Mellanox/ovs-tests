#!/bin/bash
#
#
# Test ufid is the same when queried from ovs-vswitchd and ovs-dpctl
#
# setup: veth0 <-> veth1 <-> OVS <->  veth2@ns0 <-> veth3@ns0
#        VM1_IP                                      VM2_IP
#


my_dir="$(dirname "$0")"
. $my_dir/common.sh


LOCAL_IP=99.99.99.5
REMOTE_IP=99.99.99.6
CLEAN="sed -e 's/used:.*, act/used:used, act/;s/eth(src=[a-z0-9:]*,dst=[a-z0-9:]*)/eth(macs)/;s/recirc_id(0),//;s/,ipv4(.*)//' | sort"

function cleanup() {
    echo "cleanup"
    start_clean_openvswitch
    ip link del dev veth2 &> /dev/null
    ip link del dev veth0 &> /dev/null
    ip netns del red &> /dev/null
    ip netns del blue &> /dev/null
}
cleanup

echo "setup netns"
ip netns add red
ip netns add blue
ip link add veth2 type veth peer name veth3
ip link add veth0 type veth peer name veth1
ip link set veth1 netns red
ip netns exec red ip addr add $LOCAL_IP/24 dev veth1
ip netns exec red ip link set veth1 up
ip link set veth3 netns blue
ip netns exec blue ip addr add $REMOTE_IP/24 dev veth3
ip netns exec blue ip link set veth3 up
ifconfig veth2 up
ifconfig veth0 up

echo "clean ovs"
del_all_bridges
systemctl restart openvswitch
sleep 2
del_all_bridges

echo "prep ovs"
ovs-vsctl add-br br3
ovs-vsctl add-port br3 veth0
ovs-vsctl add-port br3 veth2

# generate rule
ip netns exec red ping $REMOTE_IP -i 0.25 -c 8 

# start test

title "Get ufid from appctl dpct/dump-flows"
UFID=`ovs-appctl dpctl/dump-flows -m type=offloaded | grep 0x0800 | grep "in_port(veth2)" | cut -d , -f 1`
echo $UFID
test -n "$UFID" && success || fail

title "Get ufid from dpctl dump-flows and compare"
UFID2=`ovs-dpctl dump-flows -m type=offloaded | grep 0x0800 | grep "in_port(veth2)" | cut -d , -f 1 | grep $UFID`
echo $UFID2
test -n "$UFID2" && success || fail

title "Check tc show can see a cookie"
COOKIE=`tc -s filter show  dev veth2 protocol ip ingress | grep cookie`
echo $COOKIE
test -n "$COOKIE" && success || fail

# end test

cleanup
echo "done"
