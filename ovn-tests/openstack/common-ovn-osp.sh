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

# Physical Networks
PROVIDER_NETWORK="provider-net"

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
