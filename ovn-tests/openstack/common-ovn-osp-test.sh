OVN_OSP_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
. $OVN_OSP_DIR/../common-ovn-test.sh
. $OVN_OSP_DIR/common-ovn-osp.sh

function config_ovn_pf_provider_net() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local vf_var=$3
    local rep_var=$4
    local network=${5:-$PROVIDER_NETWORK_A}

    config_sriov_switchdev_mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovn_add_network $OVN_PF_BRIDGE $NIC $network
    ovn_config_mtu $NIC $OVN_PF_BRIDGE
    ip addr add $ovn_controller_ip/24 dev $OVN_PF_BRIDGE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_ovn_pf_vlan_provider_net() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local vf_var=$3
    local rep_var=$4
    local network=${5:-$PROVIDER_NETWORK_A}

    config_sriov_switchdev_mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovs_create_bridge_vlan_interface
    ovn_add_network $OVN_PF_BRIDGE $NIC $network
    ovn_config_mtu $NIC $OVN_PF_BRIDGE $OVN_VLAN_INTERFACE
    ip addr add $ovn_controller_ip/24 dev $OVN_VLAN_INTERFACE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_ovn_vf_lag_provider_net() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local vf_var=$3
    local rep_var=$4
    local network=${5:-$PROVIDER_NETWORK_A}

    config_vf_lag
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovn_add_network $OVN_PF_BRIDGE $OVN_BOND $network
    ovn_config_mtu $NIC $NIC2 $OVN_BOND $OVN_PF_BRIDGE
    ip addr add $ovn_controller_ip/24 dev $OVN_PF_BRIDGE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_ovn_vf_lag_vlan_provider_net() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local vf_var=$3
    local rep_var=$4
    local network=${5:-$PROVIDER_NETWORK_A}

    config_vf_lag
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovs_create_bridge_vlan_interface
    ovn_add_network $OVN_PF_BRIDGE $OVN_BOND $network
    ovn_config_mtu $NIC $NIC2 $OVN_BOND $OVN_PF_BRIDGE $OVN_VLAN_INTERFACE
    ip addr add $ovn_controller_ip/24 dev $OVN_VLAN_INTERFACE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}
