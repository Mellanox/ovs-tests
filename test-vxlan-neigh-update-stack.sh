#!/bin/bash
#
# Test to reproduce wrong device on neigh update with stacked devices (e.g. bond)
# We assume the neigh device is an mlx5 device, and access it's priv as mlx5e_priv.
# To actually crash, the refcount release in neigh update, which is in workqueue,
# needs to happen after the rule is deleted. so we need to delete a lot of rules
# to catch this.
#
# Bug SW #1756603: VF-LAG LACP with Nuage VRS - OpenVswitch restart result kernel Freeze
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev_if_no_rep $REP
bind_vfs

local_ip="2.2.2.2"
remote_ip="2.2.2.3"
dst_port=1234
id=98

pid=0
function killpid() {
    [ $pid != 0 ] && kill $pid &>/dev/null && wait $pid &>/dev/null && pid=0
}

function cleanup() {
    ip link del dev vxlan1 &> /dev/null
    ip link del dev veth0 &> /dev/null
    killpid
}
trap cleanup EXIT

function config() {
    ip link add vxlan1 type vxlan dstport $dst_port external
    ip link add veth0 type veth peer name veth1
    ip link set vxlan1 up
    ip link set veth0 up
    ip link set veth1 up
    ip addr add ${local_ip}/24 dev veth0
}

function background_update() {
    for i in `seq 10 50` ; do
	for j in `seq 10 99` ; do
		ip n replace ${remote_ip} dev veth0 lladdr e4:22:33:44:${j}:${i}
		sleep 0.005
	done
    done
}

function neigh_update_test() {
    local local_ip="$1"
    local remote_ip="$2"

    echo "local_ip $local_ip remote_ip $remote_ip"

    reset_tc $REP
    wait_for_linkup $NIC

    background_update &
    pid=$!

    echo "running.."
    # 1000 iterations as sometimes it takes a long time to crash.
    for i in `seq 1000`; do
	tc_filter add dev $REP protocol ip parent ffff: prio 1 \
		flower dst_mac e4:22:33:44:55:66 skip_sw \
		action tunnel_key set \
		id $id src_ip ${local_ip} dst_ip ${remote_ip} dst_port ${dst_port} \
		action mirred egress redirect dev vxlan1
	sleep 0.02
	tc filter del dev $REP prio 1 ingress
    done
    echo "done"
    killpid
}

function test_neigh_update_ipv4() {
    title "Test neigh update ipv4"
    cleanup
    config
    neigh_update_test $local_ip $remote_ip
}


test_neigh_update_ipv4
test_done
