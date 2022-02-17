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

function config_ovn_k8s_pf_vlan() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local ovn_controller_ip_mask=$3
    local ovn_controller_mac=$4
    local ovn_tunnel_ip=$5
    local vf_var=$6
    local rep_var=$7

    config_sriov_switchdev_mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovn_add_network $BRIDGE $NIC $OVN_KUBERNETES_NETWORK
    ovs_create_bridge_vlan_interface $BRIDGE

    ovn_config_mtu $NIC $BRIDGE $OVN_VLAN_INTERFACE
    ip link set $NIC addr $ovn_controller_mac
    ip addr add $ovn_controller_ip/$ovn_controller_ip_mask dev $BRIDGE
    ip addr add $ovn_tunnel_ip/24 dev $OVN_VLAN_INTERFACE

    ovn_set_ovs_config $ovn_central_ip $ovn_tunnel_ip
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

function config_ovn_k8s_hairpin() {
    local ovn_ip=${1:-$OVN_LOCAL_CENTRAL_IP}

    ovn_start_northd_central
    ovn_create_topology

    config_sriov_switchdev_mode
    require_interfaces CLIENT_VF CLIENT_REP

    start_clean_openvswitch
    ovn_set_ovs_config $ovn_ip $ovn_ip
    ovn_start_ovn_controller
}
