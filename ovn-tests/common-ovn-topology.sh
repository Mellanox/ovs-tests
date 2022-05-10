# Topologies
OVN_TOPO_DIR="$OVN_DIR/ovn-topologies"
TOPOLOGY_SINGLE_SWITCH="$OVN_TOPO_DIR/single-switch.yaml"
TOPOLOGY_2_SWITCHES="$OVN_TOPO_DIR/two-switches.yaml"
TOPOLOGY_SINGLE_ROUTER_2_SWITCHES="$OVN_TOPO_DIR/single-router-2-switches.yaml"
TOPOLOGY_GATEWAY_ROUTER="$OVN_TOPO_DIR/gateway-router.yaml"
TOPOLOGY_OVN_KUBERNETES="$OVN_TOPO_DIR/ovn-kubernetes.yaml"
TOPOLOGY_DISTRIBUTED_GATEWAY_PORT="$OVN_TOPO_DIR/distributed-gateway-port.yaml"
TOPOLOGY_OPENSTACK="$OVN_TOPO_DIR/openstack.yaml"

function ovn_create_topology() {
    local topology_file=${1:-$TOPOLOGY}

    $OVN_DIR/ovn-topology-creator.py -f "$topology_file" -c
    ovn-nbctl show
}

function ovn_destroy_topology() {
    local topology_file=${1:-$TOPOLOGY}

    $OVN_DIR/ovn-topology-creator.py -f "$topology_file" -d
}

function ovn_parse_topology() {
    local topology=$1
    local attr=${2:-"."}

    yq eval "$attr" $topology
}

function ovn_get_topology() {
    local topology=$1
    local attr=${2:-"."}

    ovn_parse_topology $topology ".topology | $attr"
}

function ovn_get_switches() {
    local topology=$1
    local attr=${2:-"."}

    ovn_get_topology $topology ".[] | select(.type == \"switch\") | collect | $attr"
}

function ovn_get_switch() {
    local topology=$1
    local switch=$2
    local attr=${3:-"."}

    ovn_get_switches $topology ".[] | select(.name == \"$switch\") | $attr"
}

# Get OVN switch with VIF port (port type is null)
function ovn_get_switch_name_with_vif_port() {
    local topology=$1
    local index=${2:-0}

    ovn_get_switches $topology ".[] | select(.ports.[] | select(.type == null)) | collect | .[$index].name"
}

function ovn_get_switch_ports() {
    local topology=$1
    local switch=$2
    local attr=${3:-"."}

    ovn_get_switch $topology $switch ".ports | $attr"
}

# Get OVN switch VIF port (port type is null) with given index (default 0)
function ovn_get_switch_vif_port_name() {
    local topology=$1
    local switch=$2
    local index=${3:-0}

    ovn_get_switch_ports $topology $switch ".[] | select(.type == null) | collect | .[$index].name" -
}

function ovn_get_switch_port() {
    local topology=$1
    local switch=$2
    local port=$3
    local attr=${4:-"."}

    ovn_get_switch_ports $topology $switch ".[] | select(.name == \"$port\") | $attr"
}

function ovn_get_switch_port_mac() {
    local topology=$1
    local switch=$2
    local port=$3

    ovn_get_switch_port $topology $switch $port ".mac"
}

function ovn_get_switch_port_ip() {
    local topology=$1
    local switch=$2
    local port=$3
    local index=${4:-0}

    ovn_get_switch_port $topology $switch $port ".ipv4[$index]"
}

function ovn_get_switch_port_ipv6() {
    local topology=$1
    local switch=$2
    local port=$3
    local index=${4:-0}

    ovn_get_switch_port $topology $switch $port ".ipv6[$index]"
}

# Get router port that connected given switch
function ovn_get_router_port_name_for_switch() {
    local topology=$1
    local switch=$2

    ovn_get_switch_ports $topology $switch ".[] | select(.type == \"router\").routerPort"
}

function ovn_get_routers() {
    local topology=$1
    local attr=${2:-"."}

    ovn_get_topology $topology ".[] | select(.type == \"router\") | collect | $attr"
}

function ovn_get_router() {
    local topology=$1
    local router=$2
    local attr=${3:-"."}

    ovn_get_topology $topology ".[] | select(.name == \"$router\") | $attr"
}

function ovn_get_router_ports() {
    local topology=$1
    local router=$2
    local attr=${3:-"."}

    ovn_get_router $topology $router ".ports | $attr"
}

function ovn_get_router_port() {
    local topology=$1
    local router=$2
    local port=$3
    local attr=${4:-"."}

    ovn_get_router_ports $topology $router ".[] | select(.name == \"$port\") | $attr"
}

function ovn_get_router_port_mac() {
    local topology=$1
    local router=$2
    local port=$3
    local index=${4:-0}

    ovn_get_router_port $topology $router $port ".mac" | cut -d / -f1
}

function ovn_get_router_port_ip() {
    local topology=$1
    local router=$2
    local port=$3
    local index=${4:-0}

    ovn_get_router_port $topology $router $port ".ipv4[$index]" | cut -d / -f1
}

function ovn_get_router_port_ip_mask() {
    local topology=$1
    local router=$2
    local port=$3
    local index=${4:-0}

    ovn_get_router_port $topology $router $port ".ipv4[$index]" | cut -d / -f2
}

function ovn_get_router_port_ipv6() {
    local topology=$1
    local router=$2
    local port=$3
    local index=${4:-0}

    ovn_get_router_port $topology $router $port ".ipv6[$index]" | cut -d / -f1
}

function ovn_get_router_port_for_switch() {
    local topology=$1
    local switch=$2
    local attr=${3:-"."}

    local router_port=$(ovn_get_router_port_name_for_switch $topology $switch)
    ovn_get_routers $topology ".[].ports[] | select(.name == \"$router_port\") | $attr"
}

function ovn_get_switch_gateway_ip() {
    local topology=$1
    local switch=$2
    local index=${3:-0}

    ovn_get_router_port_for_switch $topology $switch ".ipv4[$index]" | cut -d / -f1
}

function ovn_get_switch_gateway_ipv6() {
    local topology=$1
    local switch=$2
    local index=${3:-0}

    ovn_get_router_port_for_switch $topology $switch ".ipv6[$index]" | cut -d / -f1
}

function ovn_get_load_balancers() {
    local topology=$1
    local attr=${2:-"."}

    ovn_get_topology $topology ".[] | select(.type == \"loadBalancer\") | collect | $attr"
}

function ovn_get_load_balancer() {
    local topology=$1
    local lb=$2
    local attr=${3:-"."}

    ovn_get_load_balancers $topology ".[] | select(.name == \"$lb\") | $attr"
}

function ovn_get_load_balancer_vip() {
    local topology=$1
    local lb=$2
    local index=${3:-0}

    ovn_get_load_balancer $topology $lb ".vip"
}

function read_single_switch_topology() {
    TOPOLOGY=$TOPOLOGY_SINGLE_SWITCH
    CLIENT_SWITCH=$SWITCH1
    CLIENT_PORT=$SWITCH1_PORT1
    SERVER_SWITCH=$SWITCH1
    SERVER_PORT=$SWITCH1_PORT2

    read_switch_client
    read_switch_server
}

function read_switch_client() {
    CLIENT_MAC=$(ovn_get_switch_port_mac $TOPOLOGY $CLIENT_SWITCH $CLIENT_PORT)
    CLIENT_IPV4=$(ovn_get_switch_port_ip $TOPOLOGY $CLIENT_SWITCH $CLIENT_PORT)
    CLIENT_IPV6=$(ovn_get_switch_port_ipv6 $TOPOLOGY $CLIENT_SWITCH $CLIENT_PORT)
    CLIENT_NS=${TRAFFIC_INFO['client_ns']}
    CLIENT_VF=${TRAFFIC_INFO['client_vf']}
    CLIENT_REP=${TRAFFIC_INFO['client_rep']}
}

function read_switch_server() {
    SERVER_MAC=$(ovn_get_switch_port_mac $TOPOLOGY $SERVER_SWITCH $SERVER_PORT)
    SERVER_IPV4=$(ovn_get_switch_port_ip $TOPOLOGY $SERVER_SWITCH $SERVER_PORT)
    SERVER_IPV6=$(ovn_get_switch_port_ipv6 $TOPOLOGY $SERVER_SWITCH $SERVER_PORT)
    SERVER_NS=${TRAFFIC_INFO['server_ns']}
    SERVER_VF=${TRAFFIC_INFO['server_vf']}
    SERVER_REP=${TRAFFIC_INFO['server_rep']}
}

function read_two_switches_topology() {
    TOPOLOGY=$TOPOLOGY_2_SWITCHES
    CLIENT_SWITCH=$SWITCH1
    CLIENT_PORT=$SWITCH1_PORT1
    SERVER_SWITCH=$SWITCH2
    SERVER_PORT=$SWITCH2_PORT1

    read_switch_client
    read_switch_server
}

function read_single_router_two_switches_topology() {
    TOPOLOGY=$TOPOLOGY_SINGLE_ROUTER_2_SWITCHES
    CLIENT_SWITCH=$SWITCH1
    CLIENT_PORT=$SWITCH1_PORT1
    SERVER_SWITCH=$SWITCH2
    SERVER_PORT=$SWITCH2_PORT1

    read_router_client
    read_router_server
}

function read_router_client() {
    read_switch_client
    CLIENT_GATEWAY_IPV4=$(ovn_get_switch_gateway_ip $TOPOLOGY $CLIENT_SWITCH)
    CLIENT_GATEWAY_IPV6=$(ovn_get_switch_gateway_ipv6 $TOPOLOGY $CLIENT_SWITCH)
}

function read_router_server() {
    read_switch_server
    SERVER_GATEWAY_IPV4=$(ovn_get_switch_gateway_ip $TOPOLOGY $SERVER_SWITCH)
    SERVER_GATEWAY_IPV6=$(ovn_get_switch_gateway_ipv6 $TOPOLOGY $SERVER_SWITCH)
}

function read_gateway_router_topology() {
    TOPOLOGY=$TOPOLOGY_GATEWAY_ROUTER
    CLIENT_SWITCH=$SWITCH1
    CLIENT_PORT=$SWITCH1_PORT1
    read_router_client

    SERVER_ROUTER=$GATEWAY_ROUTER
    SERVER_ROUTER_PORT=$GATEWAY_ROUTER_PORT
    read_gateway_server
}

function read_distributed_gateway_port_topology() {
    TOPOLOGY=$TOPOLOGY_DISTRIBUTED_GATEWAY_PORT
    CLIENT_SWITCH=$SWITCH1
    CLIENT_PORT=$SWITCH1_PORT1
    read_router_client

    SERVER_ROUTER=$ROUTER
    SERVER_ROUTER_PORT=$ROUTER_GATEWAY_PORT
    read_gateway_server
}

function read_gateway_server() {
    SERVER_IPV4=$OVN_EXTERNAL_NETWORK_HOST_IP
    SERVER_IPV6=$OVN_EXTERNAL_NETWORK_HOST_IP_V6
    SERVER_GATEWAY_IPV4=$(ovn_get_router_port_ip $TOPOLOGY $SERVER_ROUTER $SERVER_ROUTER_PORT)
    SERVER_GATEWAY_IPV6=$(ovn_get_router_port_ipv6 $TOPOLOGY $SERVER_ROUTER $SERVER_ROUTER_PORT)
    SERVER_PORT=$NIC
}
