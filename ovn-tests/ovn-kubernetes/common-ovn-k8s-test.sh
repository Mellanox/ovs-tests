OVN_K8S_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
. $OVN_K8S_DIR/../common-ovn-test.sh
. $OVN_K8S_DIR/common-ovn-k8s.sh

function config_ovn_k8s_pf() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local ovn_controller_ip_mask=$3
    local ovn_controller_mac=$4
    local vf_var=$5
    local rep_var=$6

    config_sriov_switchdev_mode
    require_interfaces $vf_var $rep_var

    config_ovn_k8s_pf_ext_server $ovn_central_ip $ovn_controller_ip $ovn_controller_ip_mask $ovn_controller_mac
}

function config_ovn_k8s_pf_ext_server() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local ovn_controller_ip_mask=$3
    local ovn_controller_mac=$4

    start_clean_openvswitch
    ovn_add_network $BRIDGE $NIC $OVN_KUBERNETES_NETWORK
    ovn_config_mtu $NIC $BRIDGE
    ip link set $NIC addr $ovn_controller_mac
    ip addr add $ovn_controller_ip/$ovn_controller_ip_mask dev $BRIDGE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_ovn_k8s_pf_vlan() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local ovn_controller_ip_mask=$3
    local ovn_controller_mac=$4
    local ovn_tunnel_ip=$5
    local vf_var=$6
    local rep_var=$7

    config_sriov_switchdev_mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovn_add_network $BRIDGE $NIC $OVN_KUBERNETES_NETWORK
    ovs_create_bridge_vlan_interface $BRIDGE

    ovn_config_mtu $NIC $BRIDGE $OVN_VLAN_INTERFACE
    ip link set $NIC addr $ovn_controller_mac
    ip addr add $ovn_controller_ip/$ovn_controller_ip_mask dev $BRIDGE
    ip addr add $ovn_tunnel_ip/24 dev $OVN_VLAN_INTERFACE

    ovn_set_ovs_config $ovn_central_ip $ovn_tunnel_ip
    ovn_start_ovn_controller
}

function config_ovn_k8s_vf_lag() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local ovn_controller_ip_mask=$3
    local ovn_controller_mac=$4
    local vf_var=$5
    local rep_var=$6
    local mode=${7:-"802.3ad"}

    config_vf_lag $mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovn_add_network $BRIDGE $OVN_BOND $OVN_KUBERNETES_NETWORK
    ovn_config_mtu $NIC $NIC2 $OVN_BOND $BRIDGE
    ip link set $OVN_BOND addr $ovn_controller_mac
    ip addr add $ovn_controller_ip/$ovn_controller_ip_mask dev $BRIDGE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_ovn_k8s_hairpin() {
    local ovn_ip=${1:-$OVN_LOCAL_CENTRAL_IP}

    ovn_start_northd_central
    ovn_create_topology

    config_sriov_switchdev_mode
    require_interfaces CLIENT_VF CLIENT_REP

    start_clean_openvswitch
    ovn_set_ovs_config $ovn_ip $ovn_ip
    ovn_start_ovn_controller
}

function config_ovn_k8s_vf_lag_vlan() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local ovn_controller_ip_mask=$3
    local ovn_controller_mac=$4
    local ovn_tunnel_ip=$5
    local vf_var=$6
    local rep_var=$7
    local mode=${8:-"802.3ad"}

    config_vf_lag $mode
    require_interfaces $vf_var $rep_var

    start_clean_openvswitch
    ovn_add_network $BRIDGE $OVN_BOND $OVN_KUBERNETES_NETWORK
    ovs_create_bridge_vlan_interface $BRIDGE

    ovn_config_mtu $NIC $NIC2 $OVN_BOND $BRIDGE $OVN_VLAN_INTERFACE
    ip link set $OVN_BOND addr $ovn_controller_mac
    ip addr add $ovn_controller_ip/$ovn_controller_ip_mask dev $BRIDGE
    ip addr add $ovn_tunnel_ip/24 dev $OVN_VLAN_INTERFACE

    ovn_set_ovs_config $ovn_central_ip $ovn_tunnel_ip
    ovn_start_ovn_controller
}
