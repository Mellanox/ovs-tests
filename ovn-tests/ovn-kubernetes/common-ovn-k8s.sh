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

function config_ovn_k8s_pf() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local ovn_controller_ip_mask=$3
    local ovn_controller_mac=$4
    local vf_var=$5
    local rep_var=$6

    config_sriov_switchdev_mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovn_add_network $BRIDGE $NIC $OVN_KUBERNETES_NETWORK
    ovn_config_mtu $NIC $BRIDGE
    ip link set $NIC addr $ovn_controller_mac
    ip addr add $ovn_controller_ip/$ovn_controller_ip_mask dev $BRIDGE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_ovn_k8s_vf_lag() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local ovn_controller_ip_mask=$3
    local ovn_controller_mac=$4
    local vf_var=$5
    local rep_var=$6
    local mode=${7:-"802.3ad"}

    config_vf_lag $mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovn_add_network $BRIDGE $OVN_BOND $OVN_KUBERNETES_NETWORK
    ovn_config_mtu $NIC $NIC2 $OVN_BOND $BRIDGE
    ip link set $OVN_BOND addr $ovn_controller_mac
    ip addr add $ovn_controller_ip/$ovn_controller_ip_mask dev $BRIDGE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}
