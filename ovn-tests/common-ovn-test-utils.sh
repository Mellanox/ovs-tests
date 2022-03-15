OVN_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" &>/dev/null && pwd)

. $OVN_DIR/../common.sh
. $OVN_DIR/common-ovn.sh
. $OVN_DIR/common-ovn-topology.sh

# OVN IPs
OVN_LOCAL_CENTRAL_IP="127.0.0.1"
OVN_CENTRAL_IP="192.168.100.100"
OVN_CENTRAL_IPV6="192:168:100::100"
OVN_REMOTE_CONTROLLER_IP="192.168.100.101"
OVN_REMOTE_CONTROLLER_IPV6="192:168:100::101"

OVN_EXTERNAL_NETWORK_HOST_IP="172.16.1.10"
OVN_EXTERNAL_NETWORK_HOST_IP_V6="172:16:1::A"

OVN_TUNNEL_MTU=1700

OVN_PF_BRIDGE="br-pf"
OVN_VLAN_INTERFACE="vlan-int"
OVN_VLAN_TAG=100

OVN_EXTERNAL_NETWORK="PhyNet"

# OVN Gateway Router
GATEWAY_ROUTER=gw0
GATEWAY_ROUTER_PORT=gw0-outside

# OVN Switches
SWITCH1=sw0
SWITCH2=sw1

# OVN Switch Ports
SWITCH1_PORT1=sw0-port1
SWITCH1_PORT2=sw0-port2
SWITCH2_PORT1=sw1-port1

# Test Config
CONFIG_REMOTE=${CONFIG_REMOTE:-}
# Check if remote host exist
HAS_BOND=${HAS_BOND:-}

function __reset_nic() {
    local nic=${NIC:-}

    ip link set $nic down
    ip addr flush dev $nic
    ip link set $nic mtu 1500
}

function __ovn_clean_up() {
    ovs_conf_remove max-idle
    ovn_stop_ovn_controller
    ovn_remove_ovs_config
    ovs_clear_bridges

    __reset_nic
    ip -all netns del

    if [[ -n "$HAS_BOND" ]]; then
        unbind_vfs
        unbind_vfs $NIC2
        clear_bonding
        disable_sriov_port2
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

function ovn_config_mtu() {
    local nic
    for nic in $@; do
        ip link set $nic mtu $OVN_TUNNEL_MTU
        ip link set $nic up
    done
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

    ovn_start_northd_central
    ovn_create_topology

    config_sriov_switchdev_mode
    require_interfaces CLIENT_VF CLIENT_REP

    start_clean_openvswitch
    ovn_add_network
    ip link set $NIC up

    ovn_set_ovs_config $ovn_ip $ovn_ip
    ovn_start_ovn_controller
}

function config_ovn_external_server() {
    on_remote_exec "
    ip link set $SERVER_PORT up
    ip addr add $SERVER_IPV4/24 dev $SERVER_PORT
    ip -6 addr add $SERVER_IPV6/124 dev $SERVER_PORT

    ip route add $CLIENT_IPV4 via $SERVER_GATEWAY_IPV4 dev $SERVER_PORT
    ip -6 route add $CLIENT_IPV6 via $SERVER_GATEWAY_IPV6 dev $SERVER_PORT
    "
}

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

function ovn_set_ips() {
    ovn_central_ip=${ovn_central_ip:-$OVN_CENTRAL_IP}
    ovn_controller_ip=${ovn_controller_ip:-$OVN_CENTRAL_IP}
    ovn_remote_controller_ip=${ovn_remote_controller_ip:-$OVN_REMOTE_CONTROLLER_IP}
}

function ovn_set_ipv6_ips() {
    ovn_central_ip=${ovn_central_ip:-$OVN_CENTRAL_IPV6}
    ovn_controller_ip=${ovn_controller_ip:-$OVN_CENTRAL_IPV6}
    ovn_remote_controller_ip=${ovn_remote_controller_ip:-$OVN_REMOTE_CONTROLLER_IPV6}
}

require_ovn
