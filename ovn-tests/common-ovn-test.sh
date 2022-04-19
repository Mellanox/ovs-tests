OVN_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
. $OVN_DIR/../common.sh
. $OVN_DIR/common-ovn.sh
. $OVN_DIR/common-ovn-topology.sh
. $OVN_DIR/common-ovn-test-utils.sh

# Test Config
CONFIG_REMOTE=${CONFIG_REMOTE:-}
# Check if remote host exist
HAS_BOND=${HAS_BOND:-}

function __ovn_clean_up() {
    ovs_conf_remove max-idle
    ovn_stop_ovn_controller
    ovn_remove_ovs_config
    ovs_clear_bridges

    __reset_nic
    ip -all netns del
    ip link del $PF_VLAN_INT 2>/dev/null
    ip link del $BOND_VLAN_INT 2>/dev/null

    if [[ -n "$HAS_BOND" ]]; then
        clean_vf_lag
    fi

    config_sriov 0
}

function ovn_clean_up() {
    __ovn_clean_up
    if [[ -n "$CONFIG_REMOTE" ]]; then
        on_remote_exec "__ovn_clean_up"
    fi

    ovn_start_clean
    ovn_stop_northd_central
}

function config_sriov_switchdev_mode() {
    config_sriov
    enable_switchdev
    bind_vfs
}

function config_vf_lag() {
    local mode=${1:-"802.3ad"}

    config_sriov
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    unbind_vfs
    unbind_vfs $NIC2
    config_bonding $NIC $NIC2 $mode
    is_vf_lag_activated || fail
    bind_vfs
    bind_vfs $NIC2
}

function clean_vf_lag() {
    unbind_vfs
    unbind_vfs $NIC2
    clear_bonding
    config_sriov 0
    config_sriov 0 $NIC2
}

function config_ovn_single_node() {
    local ovn_ip=${1:-$OVN_LOCAL_CENTRAL_IP}

    ovn_start_northd_central
    ovn_create_topology

    config_sriov_switchdev_mode
    require_interfaces CLIENT_VF CLIENT_REP SERVER_VF SERVER_REP

    start_clean_openvswitch
    ovn_set_ovs_config $ovn_ip $ovn_ip
    ovn_start_ovn_controller
}

function config_ovn_pf() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local vf_var=$3
    local rep_var=$4

    config_sriov_switchdev_mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovn_config_mtu $NIC
    ip addr add $ovn_controller_ip/24 dev $NIC

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function ovn_single_node_external_config() {
    local ovn_ip=${1:-$OVN_LOCAL_CENTRAL_IP}
    local network=${2:-$OVN_EXTERNAL_NETWORK}

    ovn_start_northd_central
    ovn_create_topology

    config_sriov_switchdev_mode
    require_interfaces CLIENT_VF CLIENT_REP

    start_clean_openvswitch
    ovn_add_network $OVN_PF_BRIDGE $NIC $network
    ip link set $NIC up

    ovn_set_ovs_config $ovn_ip $ovn_ip
    ovn_start_ovn_controller
}

function config_port_ip() {
    local port=$1
    local ip=$2
    local ipv6=$3
    local ip_mask=${4:-24}
    local ipv6_mask=${5:-64}

    ip link set $port up
    ip addr add $ip/$ip_mask dev $port

    if [[ -n "$ipv6" ]]; then
        ip -6 addr add $ipv6/$ipv6_mask dev $port
    fi
}

config_ovn_external_server_ip() {
    local server_port=${1:-$NIC}
    local server_ipv4=${2:-$OVN_EXTERNAL_NETWORK_HOST_IP}
    local server_ipv6=${3:-$OVN_EXTERNAL_NETWORK_HOST_IP_V6}

    on_remote_exec "config_port_ip $server_port $server_ipv4 $server_ipv6"
}

function config_ovn_external_server_route() {
    local server_port=$1
    local gw_ipv4=$2
    local network_ipv4=$3
    local gw_ipv6=$4
    local network_ipv6=$5

    on_remote_exec "
    ip route add $network_ipv4 via $gw_ipv4 dev $server_port
    ip -6 route add $network_ipv6 via $gw_ipv6 dev $server_port
    "
}

function config_ovn_external_server() {
    config_ovn_external_server_ip $SERVER_PORT $SERVER_IPV4 $SERVER_IPV6
    config_ovn_external_server_route $SERVER_PORT $SERVER_GATEWAY_IPV4 $CLIENT_IPV4 $SERVER_GATEWAY_IPV6 $CLIENT_IPV6
}

# Config ovn with ovs internal port with vlan
function config_ovn_pf_vlan() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local vf_var=$3
    local rep_var=$4

    config_sriov_switchdev_mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovs_create_bridge_vlan_interface
    ovs_add_port_to_switch $OVN_PF_BRIDGE $NIC
    ovn_config_mtu $NIC $OVN_PF_BRIDGE $OVN_VLAN_INTERFACE
    ip addr add $ovn_controller_ip/24 dev $OVN_VLAN_INTERFACE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

# Config ovn with linux vlan interface created from NIC
function config_ovn_pf_vlan_int() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local vf_var=$3
    local rep_var=$4

    config_sriov_switchdev_mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    create_vlan_interface $NIC $PF_VLAN_INT $OVN_VLAN_TAG
    ovn_config_mtu $NIC $PF_VLAN_INT
    ip addr add $ovn_controller_ip/24 dev $PF_VLAN_INT

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_ovn_vf_lag() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local vf_var=$3
    local rep_var=$4
    local mode=${5:-"802.3ad"}

    config_vf_lag $mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovn_config_mtu $NIC $NIC2 $OVN_BOND
    ip addr add $ovn_controller_ip/24 dev $OVN_BOND

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_ovn_vf_lag_vlan() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local vf_var=$3
    local rep_var=$4
    local mode=${5:-"802.3ad"}

    config_vf_lag $mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovs_create_bridge_vlan_interface
    ovs_add_port_to_switch $OVN_PF_BRIDGE $OVN_BOND
    ovn_config_mtu $NIC $NIC2 $OVN_BOND $OVN_PF_BRIDGE $OVN_VLAN_INTERFACE
    ip addr add $ovn_controller_ip/24 dev $OVN_VLAN_INTERFACE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_ovn_vf_lag_vlan_int() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local vf_var=$3
    local rep_var=$4
    local mode=${5:-"802.3ad"}

    config_vf_lag $mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    create_vlan_interface $OVN_BOND $BOND_VLAN_INT $OVN_VLAN_TAG
    ovn_config_mtu $NIC $NIC2 $OVN_BOND $BOND_VLAN_INT
    ip addr add $ovn_controller_ip/24 dev $BOND_VLAN_INT

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function ovn_config_interface_namespace() {
    local vf=$1
    local rep=$2
    local ns=$3
    local ovn_port=$4
    local mac=$5
    local ip=$6
    local ipv6=$7
    local ip_gw=$8   # optional
    local ipv6_gw=$9 # optional

    ovn_bind_port $rep $ovn_port
    config_vf $ns $vf $rep $ip $mac
    ip netns exec $ns ip -6 addr add $ipv6/120 dev $vf

    if [[ -n "$ip_gw" ]]; then
        ip netns exec $ns ip route add default via $ip_gw dev $vf
    fi

    if [[ -n "$ipv6_gw" ]]; then
        ip netns exec $ns ip -6 route add default via $ipv6_gw dev $vf
    fi
}

require_ovn
