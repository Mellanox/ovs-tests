OVN_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" &>/dev/null && pwd)

. $OVN_DIR/../common.sh
. $OVN_DIR/common-ovn.sh
. $OVN_DIR/common-ovn-topology.sh

# OVN IPs
OVN_LOCAL_CENTRAL_IP="127.0.0.1"
OVN_CENTRAL_IP="192.168.100.100"
OVN_REMOTE_CONTROLLER_IP="192.168.100.101"

OVN_PF_BRIDGE="br-pf"
OVN_VLAN_INTERFACE="vlan-int"
OVN_VLAN_TAG=100

# Test Config
TOPOLOGY=
HAS_REMOTE=
HAS_BOND=
HAS_VLAN=
IS_FRAGMENTED=

function __ovn_clean_up() {
    ovn_stop_ovn_controller
    ovn_remove_ovs_config
    ovs_clear_bridges
    ovs_disable_hw_offload

    ip addr flush dev $NIC
    ip link set $NIC mtu 1500
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
    ovn_destroy_topology
    ovn_stop_northd_central
    __ovn_clean_up

    if [[ -n "$HAS_REMOTE" ]]; then
        on_remote_exec "__ovn_clean_up"
    fi
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
        is_vf_lag_active || fail
        bind_vfs
        bind_vfs $NIC2
    fi

    if [[ -z "$HAS_REMOTE" ]]; then
        require_interfaces VF2 REP2
    fi
}

function __ovn_config() {
    local nic=${1:-$NIC}
    local ovn_central_ip=${2:-$OVN_LOCAL_CENTRAL_IP}
    local ovn_controller_ip=${3:-$OVN_LOCAL_CENTRAL_IP}

    ovn_config_interfaces
    start_clean_openvswitch
    ovs_enable_hw_offload

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
    if [[ -n "$HAS_REMOTE" ]]; then
        ip link set $nic up
        ip addr add $ovn_controller_ip/24 dev $nic
    fi

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller

    # Increase MTU for PF NIC for fragmented non single node
    if [[ -n "$HAS_REMOTE" && -n "$IS_FRAGMENTED" ]]; then
        ip link set $nic mtu 2000
    fi
}

function ovn_config() {
    local nic=$NIC
    if [[ -n "$HAS_VLAN" ]]; then
        nic=$OVN_VLAN_INTERFACE
    elif [[ -n "$HAS_BOND" ]]; then
        nic=$OVN_BOND
    fi

    local ovn_ip=$OVN_LOCAL_CENTRAL_IP
    if [[ -n "$HAS_REMOTE" ]]; then
        ovn_ip=$OVN_CENTRAL_IP
    fi

    __ovn_config $nic $ovn_ip $ovn_ip
    ovn_start_northd_central $ovn_ip
    ovn_create_topology

    if [[ -n "$HAS_REMOTE" ]]; then
        # Decrease MTU for sender VF for non fragmented 2 nodes
        if [[ -z "$IS_FRAGMENTED" ]]; then
            ip link set $VF mtu 1300
        fi

        on_remote_exec "__ovn_config $nic $ovn_ip $OVN_REMOTE_CONTROLLER_IP"
    fi
}

require_ovn
