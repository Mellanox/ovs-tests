function config_simple_bridge() {
    ovs-vsctl --may-exist add-br br-phy -- set Bridge br-phy datapath_type=netdev -- br-set-external-id br-phy bridge-id br-phy -- set bridge br-phy fail-mode=standalone
    ovs-vsctl add-port br-phy pf -- set Interface pf type=dpdk options:dpdk-devargs=$PCI
}

function config_remote_bridge_tunnel() {
    ovs-vsctl --may-exist add-br br-int   -- set Bridge br-int datapath_type=netdev   -- br-set-external-id br-int bridge-id br-int   -- set bridge br-int fail-mode=standalone
    ovs-vsctl add-port br-int rep0 -- set Interface rep0 type=dpdk options:dpdk-devargs=$PCI,representor=[0]
    ovs-vsctl add-port br-int vxlan0   -- set interface vxlan0 type=vxlan options:flags=4 options:key=$1 options:remote_ip=$2
}

function config_local_tunnel_ip() {
    ip addr add $1/24 dev $2
    ip link set $2 up
}

function config_ns() {
    local ns=$1
    local dev=$2
    local ip_addr=$3

    ip netns add $ns
    ip link set $dev netns $ns
    ip netns exec $ns ifconfig $dev $ip_addr up
}
