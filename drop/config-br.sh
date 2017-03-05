#!/bin/sh

PF0=${1:-ens5f0}
BRIDGE=${2:-t_br0}


# del all bridges
ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br
#ovs-vsctl del-br $BRIDGE
ovs-vsctl -- add-br $BRIDGE -- set bridge $BRIDGE datapath_type=hw_netlink
ovs-vsctl -- add-port $BRIDGE ${PF0}_0
ovs-vsctl -- add-port $BRIDGE ${PF0}_1
ovs-vsctl -- add-port $BRIDGE $PF0


function reset() {
    local nic=$1
    tc qdisc del dev $nic ingress >/dev/null 2>&1
    tc qdisc add dev $nic ingress
    ethtool -K $nic hw-tc-offload on
}

for nic in $PF0 ${PF0}_0 ${PF0}_1; do
    reset $nic
    ifconfig $nic up
done
