TOPOLOGY=$TOPOLOGY_OPENSTACK

# Switches
SWITCH_NETWORK_A="sw-net-a"
SWITCH_NETWORK_B="sw-net-b"
SWITCH_NETWORK_PROVIDER="sw-net-provider"
SWITCH_NETWORK_PROVIDER_VLAN="sw-net-provider-vlan"

# Switch Ports
SWITCH_NETWORK_A_PORT1="sw-net-a-port1"
SWITCH_NETWORK_A_PORT2="sw-net-a-port2"
SWITCH_NETWORK_B_PORT1="sw-net-b-port1"
SWITCH_NETWORK_PROVIDER_PORT1="sw-net-provider-port1"
SWITCH_NETWORK_PROVIDER_PORT2="sw-net-provider-port2"
SWITCH_NETWORK_PROVIDER_VLAN_PORT1="sw-net-provider-vlan-port1"
SWITCH_NETWORK_PROVIDER_VLAN_PORT2="sw-net-provider-vlan-port2"
SWITCH_EXT_NETWORK_PORT="sw-net-ext-net"

# Physical Networks
PROVIDER_NETWORK="provider-net"
OSP_EXTERNAL_NETWORK="ext-net"

# Default gateway chassis is local host
export GW_CHASSIS=$(get_ovs_id)

function read_osp_topology_vm_vm_same_subnet() {
    CLIENT_SWITCH=$SWITCH_NETWORK_A
    CLIENT_PORT=$SWITCH_NETWORK_A_PORT1
    read_switch_client

    SERVER_SWITCH=$SWITCH_NETWORK_A
    SERVER_PORT=$SWITCH_NETWORK_A_PORT2
    read_switch_server
}

function read_osp_topology_vm_vm_different_subnets() {
    CLIENT_SWITCH=$SWITCH_NETWORK_A
    CLIENT_PORT=$SWITCH_NETWORK_A_PORT1
    read_router_client

    SERVER_SWITCH=$SWITCH_NETWORK_B
    SERVER_PORT=$SWITCH_NETWORK_B_PORT1
    read_router_server
}

function read_osp_topology_vm_vm_provider_net() {
    CLIENT_SWITCH=$SWITCH_NETWORK_PROVIDER
    CLIENT_PORT=$SWITCH_NETWORK_PROVIDER_PORT1
    read_switch_client

    SERVER_SWITCH=$SWITCH_NETWORK_PROVIDER
    SERVER_PORT=$SWITCH_NETWORK_PROVIDER_PORT2
    read_switch_server
}

function read_osp_topology_vm_vm_provider_vlan_net() {
    CLIENT_SWITCH=$SWITCH_NETWORK_PROVIDER_VLAN
    CLIENT_PORT=$SWITCH_NETWORK_PROVIDER_VLAN_PORT1
    read_switch_client

    SERVER_SWITCH=$SWITCH_NETWORK_PROVIDER_VLAN
    SERVER_PORT=$SWITCH_NETWORK_PROVIDER_VLAN_PORT2
    read_switch_server
}

function read_osp_topology_vm_ext() {
    local server_port=${1:-$NIC}

    CLIENT_SWITCH=$SWITCH_NETWORK_A
    CLIENT_PORT=$SWITCH_NETWORK_A_PORT1
    read_router_client

    SERVER_PORT=$server_port
    SERVER_IPV4=$OVN_EXTERNAL_NETWORK_HOST_IP
    SERVER_IPV6=$OVN_EXTERNAL_NETWORK_HOST_IP_V6
}

function read_osp_topology_vm_ext_snat() {
    CLIENT_SWITCH=$SWITCH_NETWORK_B
    CLIENT_PORT=$SWITCH_NETWORK_B_PORT1
    read_router_client

    SERVER_IPV4=$OVN_EXTERNAL_NETWORK_HOST_IP
    SERVER_IPV6=$OVN_EXTERNAL_NETWORK_HOST_IP_V6
}
