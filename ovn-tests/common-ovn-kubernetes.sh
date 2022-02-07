TOPOLOGY=$TOPOLOGY_OVN_KUBERNETES

# Switches
NODE1_SWITCH="node-1"
NODE2_SWITCH="node-2"

# Switch Ports
NODE1_SWITCH_PORT1="node-1-port1"
NODE1_SWITCH_PORT2="node-1-port2"
NODE2_SWITCH_PORT1="node-2-port1"

# Router
NODE1_ROUTER="GR_node-1"
NODE2_ROUTER="GR_node-2"

# Router ports
NODE1_ROUTER_PORT="rtoe-GR_node-1"
NODE2_ROUTER_PORT="rtoe-GR_node-2"

OVN_KUBERNETES_NETWORK="physnet"

# OVN-Kubernetes uses br<nic> naming schema for bridges
function nic_to_bridge() {
    local nic=$1

    echo "br$nic"
}
