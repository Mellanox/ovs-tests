OVN_K8S_BF_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
. $OVN_K8S_BF_DIR/../../common-ovn-bf-test.sh
. $OVN_K8S_BF_DIR/../common-ovn-k8s.sh

EXTERNAL_SERVER_IP="172.16.0.3"

function config_bf_ovn_k8s_pf() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local ovn_controller_ip_mask=$3
    local ovn_controller_mac=$4

    ovn_start_clean_openvswitch
    ovn_add_network $BRIDGE $BF_NIC $OVN_KUBERNETES_NETWORK
    ovn_config_mtu $BF_NIC $BRIDGE
    ip link set $BF_NIC addr $ovn_controller_mac
    ip link set $BF_NIC up
    ip addr add $ovn_controller_ip/$ovn_controller_ip_mask dev $BRIDGE

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller

    if [[ "$DPDK" == 1 ]]; then
        echo "Sleeping for 5 sec until the link is ready"
        sleep 5
    fi
}

function config_bf_ovn_k8s_pf_vlan() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local ovn_controller_ip_mask=$3
    local ovn_controller_mac=$4
    local ovn_tunnel_ip=$5

    ovn_start_clean_openvswitch
    ovn_add_network $BRIDGE $BF_NIC $OVN_KUBERNETES_NETWORK
    ovs_create_bridge_vlan_interface $BRIDGE

    ovn_config_mtu $BF_NIC $BRIDGE $OVN_VLAN_INTERFACE
    ip link set $BF_NIC addr $ovn_controller_mac
    ip link set $BF_NIC up
    ip addr add $ovn_controller_ip/$ovn_controller_ip_mask dev $BRIDGE
    ip addr add $ovn_tunnel_ip/24 dev $OVN_VLAN_INTERFACE

    ovn_set_ovs_config $ovn_central_ip $ovn_tunnel_ip
    ovn_start_ovn_controller

    if [[ "$DPDK" == 1 ]]; then
        echo "Sleeping for 5 sec until the link is ready"
        sleep 5
    fi
}

__common_ovn_bf_test_init
