# Topologies
OVN_TOPO_DIR="$OVN_DIR/ovn-topologies"
TOPOLOGY_SINGLE_SWITCH="$OVN_TOPO_DIR/single-switch.yaml"
TOPOLOGY_2_SWITCHES="$OVN_TOPO_DIR/two-switches.yaml"
TOPOLOGY_SINGLE_ROUTER_2_SWITCHES="$OVN_TOPO_DIR/single-router-2-switches.yaml"
TOPOLOGY_GATEWAY_ROUTER="$OVN_TOPO_DIR/gateway-router.yaml"
TOPOLOGY_OVN_KUBERNETES="$OVN_TOPO_DIR/ovn-kubernetes.yaml"

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

function read_gateway_topology() {
    CLIENT_SWITCH=$SWITCH1
    CLIENT_PORT=$SWITCH1_PORT1
    CLIENT_MAC=$(ovn_get_switch_port_mac $TOPOLOGY $CLIENT_SWITCH $CLIENT_PORT)
    CLIENT_IPV4=$(ovn_get_switch_port_ip $TOPOLOGY $CLIENT_SWITCH $CLIENT_PORT)
    CLIENT_IPV6=$(ovn_get_switch_port_ipv6 $TOPOLOGY $CLIENT_SWITCH $CLIENT_PORT)
    CLIENT_GATEWAY_IPV4=$(ovn_get_switch_gateway_ip $TOPOLOGY $CLIENT_SWITCH)
    CLIENT_GATEWAY_IPV6=$(ovn_get_switch_gateway_ipv6 $TOPOLOGY $CLIENT_SWITCH)
    CLIENT_NS=ns0
    CLIENT_VF=$VF
    CLIENT_REP=$REP

    SERVER_SWITCH=$SWITCH2
    SERVER_PORT=$SWITCH2_PORT1
    SERVER_MAC=$(ovn_get_switch_port_mac $TOPOLOGY $SERVER_SWITCH $SERVER_PORT)
    SERVER_IPV4=$(ovn_get_switch_port_ip $TOPOLOGY $SERVER_SWITCH $SERVER_PORT)
    SERVER_IPV6=$(ovn_get_switch_port_ipv6 $TOPOLOGY $SERVER_SWITCH $SERVER_PORT)
    SERVER_GATEWAY_IPV4=$(ovn_get_switch_gateway_ip $TOPOLOGY $SERVER_SWITCH)
    SERVER_GATEWAY_IPV6=$(ovn_get_switch_gateway_ipv6 $TOPOLOGY $SERVER_SWITCH)
    SERVER_NS=ns0
    SERVER_VF=$VF
    SERVER_REP=$REP
}
