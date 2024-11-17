#!/bin/bash
#
# Test create two SFs and create vdpa net devices for them and check traffic.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh
. $my_dir/common-vdpa.sh

min_nic_cx6dx
require_module mlx5_vdpa virtio_vdpa

SFNUM1=88
SFNUM2=89
VDPADEV1=vdpa_a
VDPADEV2=vdpa_b
OVSBR=vdpa-br

trap cleanup EXIT

function cleanup {
    ovs_clear_bridges
    ip netns del ns0 > /dev/null 2>&1
    delete_sf $rep2 > /dev/null 2>&1
    delete_sf $rep1 > /dev/null 2>&1
}

function create_vdpa_netdev {
    local sfnum=$1
    local rep
    local auxdev
    local vdpadevname=$2

    create_sf 0 $sfnum || return 1
    rep=$(sf_get_rep $sfnum)
    ovs-vsctl add-port $OVSBR $rep
    ip link set up dev $rep
    devlink port function set $rep hw_addr 00:00:00:00:00:$sfnum
    devlink port function set $rep state active
    sleep 0.5
    auxdev=$(sf_get_dev $sfnum)
    sf_enable_features $auxdev "rdma vnet"
    vdpa_wait_mgtdev $auxdev
    vdpa dev add name $vdpadevname mgmtdev auxiliary/$auxdev
    sleep 4
}

enable_switchdev $NIC
title "Test vdpa using SF on a host"

modprobe mlx5_vdpa || fail
modprobe -r vhost_vdpa > /dev/null 2>&1
modprobe virtio_vdpa || fail
start_clean_openvswitch || fail
ovs-vsctl add-br $OVSBR

create_vdpa_netdev $SFNUM1 $VDPADEV1
rep1=$(sf_get_rep $SFNUM1)
create_vdpa_netdev $SFNUM2 $VDPADEV2
rep2=$(sf_get_rep $SFNUM2)
fail_if_err

virtio_net1=$(vdpa_find_netdev $VDPADEV1) || err "Cannot find vdpa dev for $VDPADEV1"
virtio_net2=$(vdpa_find_netdev $VDPADEV2) || err "Cannot find vdpa dev for $VDPADEV2"
fail_if_err

pf=$(devlink port show | grep "flavour physical port 0" | sed -e 's/.*netdev\ //' | sed -e 's/\ .*//')
ip link set up dev $pf

ip netns add ns0
ip link set $virtio_net1 netns ns0
ip netns exec ns0 ip link set up dev $virtio_net1
ip netns exec ns0 ip addr add 7.7.7.21/24 dev $virtio_net1


ip link set up dev $virtio_net2
ip addr add 7.7.7.24/24 dev $virtio_net2
title "Test ping from $virtio_net2 on default namespace to $virtio_net1 on ns0"
ping -q -c 5 -i 0.2 -w 4 -I $virtio_net2 7.7.7.21 && success || err "Ping failed"

trap - EXIT
cleanup
test_done
