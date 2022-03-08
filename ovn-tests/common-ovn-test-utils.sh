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
TOPOLOGY=${TOPOLOGY:-}
# Config OVN on remote host
CONFIG_REMOTE=${CONFIG_REMOTE:-}
# Check if remote host exist
HAS_REMOTE=${HAS_REMOTE:-}
HAS_BOND=${HAS_BOND:-}
HAS_VLAN=${HAS_VLAN:-}
IS_FRAGMENTED=${IS_FRAGMENTED:-}
IS_IPV6_UNDERLAY=${IS_IPV6_UNDERLAY:-}

if [[ -n "$CONFIG_REMOTE" ]]; then
    HAS_REMOTE=1
fi

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

function ovn_config_interfaces() {
    require_interfaces NIC
    config_sriov
    enable_switchdev
    bind_vfs
    require_interfaces VF REP

    if [[ -n "$HAS_BOND" ]]; then
        require_interfaces NIC2
        enable_sriov_port2
        enable_switchdev $NIC2
        unbind_vfs
        config_bonding $NIC $NIC2 802.3ad
        is_vf_lag_activated || fail
        bind_vfs
        bind_vfs $NIC2
    fi

    if [[ -z "$CONFIG_REMOTE" ]]; then
        require_interfaces VF2 REP2
    fi
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

function ovn_pf_config() {
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

function __ovn_config_mtu() {
    # Increase MTU NIC for non single node
    # Geneve packet contains additional data
    if [[ -n "$CONFIG_REMOTE" ]]; then
        ip link set $NIC mtu $OVN_TUNNEL_MTU
        ip link set $NIC up

        if [[ -n "$HAS_BOND" ]]; then
            ip link set $OVN_BOND mtu $OVN_TUNNEL_MTU
            ip link set $OVN_BOND up
        fi

        if [[ -n "$HAS_VLAN" ]]; then
            ip link set $OVN_VLAN_INTERFACE mtu $OVN_TUNNEL_MTU
            ip link set $OVN_VLAN_INTERFACE up
        fi
    fi
}

function __ovn_config() {
    local nic=${1:-$NIC}
    local ovn_central_ip=${2:-$OVN_LOCAL_CENTRAL_IP}
    local ovn_controller_ip=${3:-$OVN_LOCAL_CENTRAL_IP}

    ovn_config_interfaces
    start_clean_openvswitch

    # Config VLAN
    if [[ -n "$HAS_VLAN" ]]; then
        ovs_create_bridge_vlan_interface
        if [[ -n "$HAS_BOND" ]]; then
            ovs_add_port_to_switch $OVN_PF_BRIDGE $OVN_BOND
        else
            ovs_add_port_to_switch $OVN_PF_BRIDGE $NIC
        fi
    fi

    # Config IP on nic if not single node
    if [[ -n "$CONFIG_REMOTE" ]]; then
        local subnet_mask=24
        if is_ipv6 $ovn_controller_ip; then
            subnet_mask=112
        fi

        ip link set $nic up
        ip addr add $ovn_controller_ip/$subnet_mask dev $nic
    fi

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
    ovs_conf_set max-idle 20000

    __ovn_config_mtu
}

function ovn_config() {
    local nic=$NIC
    if [[ -n "$HAS_VLAN" ]]; then
        nic=$OVN_VLAN_INTERFACE
    elif [[ -n "$HAS_BOND" ]]; then
        nic=$OVN_BOND
    fi

    local ovn_ip=$OVN_LOCAL_CENTRAL_IP
    if [[ -n "$CONFIG_REMOTE" ]]; then
        ovn_ip=$OVN_CENTRAL_IP
        if [[ -n "$IS_IPV6_UNDERLAY" ]]; then
            ovn_ip=$OVN_CENTRAL_IPV6
        fi
    fi

    __ovn_config $nic $ovn_ip $ovn_ip
    ovn_start_northd_central $ovn_ip
    ovn_create_topology

    if [[ -n "$CONFIG_REMOTE" ]]; then
        local ovn_remote_controller_ip=$OVN_REMOTE_CONTROLLER_IP
        if [[ -n "$IS_IPV6_UNDERLAY" ]]; then
            ovn_remote_controller_ip=$OVN_REMOTE_CONTROLLER_IPV6
        fi

        on_remote_exec "__ovn_config $nic $ovn_ip $ovn_remote_controller_ip"
    fi
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

# Fail if test not implementing run_test
function run_test() {
    fail "run_test() is not implemented"
}

function ovn_execute_test() {
    ovn_clean_up
    trap ovn_clean_up EXIT

    ovn_config
    run_test

    trap - EXIT
    ovn_clean_up

    test_done
}

require_ovn
if [[ -n "$HAS_REMOTE" ]]; then
    require_remote_server
fi
