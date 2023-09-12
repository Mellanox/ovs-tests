OVN_OSP_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
. $OVN_OSP_DIR/../common-ovn-test.sh
. $OVN_OSP_DIR/common-ovn-osp.sh

function config_ovn_pf_provider_net() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local vf_var=$3
    local rep_var=$4
    local network=${5:-$PROVIDER_NETWORK}

    config_sriov_switchdev_mode
    require_interfaces $vf_var $rep_var

    ovn_start_clean_openvswitch
    ovn_add_network $OVN_PF_BRIDGE $NIC $network
    ovn_config_mtu $NIC $OVN_PF_BRIDGE
    ip addr add $ovn_controller_ip/24 dev $OVN_PF_BRIDGE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_ovn_vf_lag_provider_net() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local vf_var=$3
    local rep_var=$4
    local network=${5:-$PROVIDER_NETWORK}

    config_vf_lag
    require_interfaces $vf_var $rep_var

    ovn_start_clean_openvswitch
    ovn_add_network $OVN_PF_BRIDGE $OVN_BOND $network
    ovn_config_mtu $NIC $NIC2 $OVN_BOND $OVN_PF_BRIDGE
    ip addr add $ovn_controller_ip/24 dev $OVN_PF_BRIDGE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_ovn_osp_gw_chassis_pf() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local network=${3:-$OSP_EXTERNAL_NETWORK}

    ovn_start_clean_openvswitch
    ovn_add_network $OVN_PF_BRIDGE $NIC $network
    ovn_config_mtu $NIC $OVN_PF_BRIDGE
    ip link set $NIC up
    ip addr add $ovn_controller_ip/24 dev $OVN_PF_BRIDGE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_ovn_osp_gw_chassis_pf_vlan() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local network=${3:-$OSP_EXTERNAL_NETWORK}

    ovn_start_clean_openvswitch
    create_vlan_interface $NIC $PF_VLAN_INT $OVN_VLAN_TAG
    ovn_add_network $OVN_PF_BRIDGE $NIC $network

    ip link set $NIC up
    ip link set $PF_VLAN_INT up

    ovn_config_mtu $NIC $PF_VLAN_INT $OVN_PF_BRIDGE
    ip addr add $ovn_controller_ip/24 dev $PF_VLAN_INT

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}
