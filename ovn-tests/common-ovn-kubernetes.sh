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

function read_k8s_topology_pod_pod_same_node() {
    CLIENT_SWITCH=$NODE1_SWITCH
    CLIENT_PORT=$NODE1_SWITCH_PORT1
    CLIENT_NODE_ROUTER=$NODE1_ROUTER
    CLIENT_NODE_PORT=$NODE1_ROUTER_PORT
    read_k8s_topology_pod_client

    SERVER_SWITCH=$NODE2_SWITCH
    SERVER_PORT=$NODE2_SWITCH_PORT1
    read_router_server
}

function read_k8s_topology_pod_pod_different_nodes() {
    CLIENT_SWITCH=$NODE1_SWITCH
    CLIENT_PORT=$NODE1_SWITCH_PORT1
    CLIENT_NODE_ROUTER=$NODE1_ROUTER
    CLIENT_NODE_PORT=$NODE1_ROUTER_PORT
    read_k8s_topology_pod_client

    SERVER_SWITCH=$NODE2_SWITCH
    SERVER_PORT=$NODE2_SWITCH_PORT1
    SERVER_NODE_ROUTER=$NODE2_ROUTER
    SERVER_NODE_PORT=$NODE2_ROUTER_PORT
    read_k8s_topology_pod_server
}

function read_k8s_topology_pod_client() {
    read_router_client
    read_k8s_client_node
}

function read_k8s_topology_pod_server() {
    read_router_server
    read_k8s_server_node
}

function read_k8s_client_node() {
    CLIENT_NODE_MAC=$(ovn_get_router_port_mac $TOPOLOGY $CLIENT_NODE_ROUTER $CLIENT_NODE_PORT)
    CLIENT_NODE_IP=$(ovn_get_router_port_ip $TOPOLOGY $CLIENT_NODE_ROUTER $CLIENT_NODE_PORT)
    CLIENT_NODE_IP_MASK=$(ovn_get_router_port_ip_mask $TOPOLOGY $CLIENT_NODE_ROUTER $CLIENT_NODE_PORT)
}

function read_k8s_server_node() {
    SERVER_NODE_MAC=$(ovn_get_router_port_mac $TOPOLOGY $SERVER_NODE_ROUTER $SERVER_NODE_PORT)
    SERVER_NODE_IP=$(ovn_get_router_port_ip $TOPOLOGY $SERVER_NODE_ROUTER $SERVER_NODE_PORT)
    SERVER_NODE_IP_MASK=$(ovn_get_router_port_ip_mask $TOPOLOGY $SERVER_NODE_ROUTER $SERVER_NODE_PORT)
}
