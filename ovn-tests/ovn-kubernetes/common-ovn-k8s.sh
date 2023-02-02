TOPOLOGY=$TOPOLOGY_OVN_KUBERNETES

# Switches
NODE1_SWITCH="node-1"
NODE2_SWITCH="node-2"

# Switch Ports
NODE1_SWITCH_PORT1="node-1-port1"
NODE1_SWITCH_PORT2="node-1-port2"
NODE2_SWITCH_PORT1="node-2-port1"
NODE2_SWITCH_PORT2="node-2-port2"

# Router
NODE1_ROUTER="GR_node-1"
NODE2_ROUTER="GR_node-2"

# Router ports
NODE1_ROUTER_PORT="rtoe-GR_node-1"
NODE2_ROUTER_PORT="rtoe-GR_node-2"

# Load Balancers
K8S_LB_IPV4="ovn-k8s-load-balancer-ipv4"
K8S_LB_IPV6="ovn-k8s-load-balancer-ipv6"

OVN_KUBERNETES_NETWORK="physnet"

# VLAN IPs
OVN_K8S_VLAN_NODE1_TUNNEL_IP="192.168.110.100"
OVN_K8S_VLAN_NODE2_TUNNEL_IP="192.168.110.101"

BRIDGE="br-phy"

function read_k8s_topology_pod_pod_same_node() {
    CLIENT_SWITCH=$NODE1_SWITCH
    CLIENT_PORT=$NODE1_SWITCH_PORT1
    CLIENT_NODE_ROUTER=$NODE1_ROUTER
    CLIENT_NODE_PORT=$NODE1_ROUTER_PORT
    read_k8s_topology_pod_client

    SERVER_SWITCH=$NODE1_SWITCH
    SERVER_PORT=$NODE1_SWITCH_PORT2
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

function read_k8s_service() {
    LB_IPV4=$(ovn_get_load_balancer_vip $TOPOLOGY $K8S_LB_IPV4)
    LB_IPV6=$(ovn_get_load_balancer_vip $TOPOLOGY $K8S_LB_IPV6)
}

function read_k8s_topology_pod_service_same_node() {
    CLIENT_SWITCH=$NODE2_SWITCH
    CLIENT_PORT=$NODE2_SWITCH_PORT1
    CLIENT_NODE_ROUTER=$NODE2_ROUTER
    CLIENT_NODE_PORT=$NODE2_ROUTER_PORT
    read_k8s_topology_pod_client

    SERVER_SWITCH=$NODE2_SWITCH
    SERVER_PORT=$NODE2_SWITCH_PORT2
    read_router_server

    read_k8s_service
}

function read_k8s_topology_pod_service_hairpin() {
    CLIENT_SWITCH=$NODE2_SWITCH
    CLIENT_PORT=$NODE2_SWITCH_PORT2
    read_k8s_topology_pod_client
    read_k8s_service
}

function read_k8s_topology_pod_service_different_nodes() {
    CLIENT_SWITCH=$NODE1_SWITCH
    CLIENT_PORT=$NODE1_SWITCH_PORT1
    CLIENT_NODE_ROUTER=$NODE1_ROUTER
    CLIENT_NODE_PORT=$NODE1_ROUTER_PORT
    read_k8s_topology_pod_client

    SERVER_SWITCH=$NODE2_SWITCH
    SERVER_PORT=$NODE2_SWITCH_PORT2
    SERVER_NODE_ROUTER=$NODE2_ROUTER
    SERVER_NODE_PORT=$NODE2_ROUTER_PORT
    read_k8s_topology_pod_server

    read_k8s_service
}

function read_k8s_topology_pod_ext() {
    local server_port=$1

    CLIENT_SWITCH=$NODE1_SWITCH
    CLIENT_PORT=$NODE1_SWITCH_PORT1
    CLIENT_NODE_ROUTER=$NODE1_ROUTER
    CLIENT_NODE_PORT=$NODE1_ROUTER_PORT
    read_k8s_topology_pod_client

    SERVER_NODE_ROUTER=$NODE2_ROUTER
    SERVER_NODE_PORT=$NODE2_ROUTER_PORT
    read_k8s_server_node
    SERVER_IPV4=$SERVER_NODE_IP
}
