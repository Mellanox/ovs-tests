# Topologies
OVN_TOPO_DIR="$OVN_DIR/ovn-topologies"
TOPOLOGY_SINGLE_SWITCH="$OVN_TOPO_DIR/single-switch.yaml"
TOPOLOGY_2_SWITCHES="$OVN_TOPO_DIR/two-switches.yaml"
TOPOLOGY_SINGLE_ROUTER_2_SWITCHES="$OVN_TOPO_DIR/single-router-2-switches.yaml"

function ovn_create_topology() {
    local topology_file=$1

    $OVN_DIR/ovn-topology-creator.py -f "$topology_file" -c
    ovn-nbctl show
}

function ovn_destroy_topology() {
    local topology_file=$1

    $OVN_DIR/ovn-topology-creator.py -f "$topology_file" -d
}
