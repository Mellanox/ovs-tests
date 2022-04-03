TOPOLOGY=$TOPOLOGY_OPENSTACK

# Switches
SWITCH_NETWORK_A="sw-net-a"
SWITCH_NETWORK_B="sw-net-b"

# Switch Ports
SWITCH_NETWORK_A_PORT1="sw-net-a-port1"
SWITCH_NETWORK_A_PORT2="sw-net-a-port2"
SWITCH_NETWORK_B_PORT1="sw-net-b-port1"

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
