OVN_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
. $OVN_DIR/common-ovn.sh
. $OVN_DIR/../common-bf.sh

TRAFFIC_INFO['bf_traffic']=1

function __config_bf_ovn_interface_namespace() {
    local vf=$1
    local ns=$2
    local mac=$3
    local ip=$4
    local ipv6=$5
    local ip_gw=$6   # optional
    local ipv6_gw=$7 # optional

    __config_vf $ns $vf $ip $mac
    ip netns exec $ns ip -6 addr add $ipv6/64 dev $vf

    if [[ -n "$ip_gw" ]]; then
        ip netns exec $ns ip route add default via $ip_gw dev $vf
    fi

    if [[ -n "$ipv6_gw" ]]; then
        ip netns exec $ns ip -6 route add default via $ipv6_gw dev $vf
    fi
}

function __config_bf_ovn_rep() {
    local rep=$1
    local ovn_port=$2

    __config_rep $rep
    ovn_bind_port $rep $ovn_port
}

function config_bf_ovn_interface_namespace() {
    local vf=$1
    local rep=$2
    local ns=$3
    local ovn_port=$4
    local mac=$5
    local ip=$6
    local ipv6=$7
    local ip_gw=$8   # optional
    local ipv6_gw=$9 # optional

    __config_bf_ovn_interface_namespace $vf $ns $mac $ip $ipv6 $ip_gw $ipv6_gw
    on_bf_exec "__config_bf_ovn_rep $rep $ovn_port"

    debug "Sleeping after configuring interface $vf namespace $ns"
    sleep 7
}

function config_bf_ovn_remote_interface_namespace() {
    local vf=$1
    local rep=$2
    local ns=$3
    local ovn_port=$4
    local mac=$5
    local ip=$6
    local ipv6=$7
    local ip_gw=$8   # optional
    local ipv6_gw=$9 # optional

    on_remote_exec "__config_bf_ovn_interface_namespace $vf $ns $mac $ip $ipv6 $ip_gw $ipv6_gw"
    on_remote_bf_exec "__config_bf_ovn_rep $rep $ovn_port"

    debug "Sleeping after configuring interface $vf namespace $ns"
    sleep 7
}

function config_bf_ovn_single_node() {
    local ovn_ip=${1:-$OVN_LOCAL_CENTRAL_IP}

    config_sriov
    unbind_vfs
    bind_vfs
    require_interfaces CLIENT_VF SERVER_VF

    on_bf_exec "ovn_start_northd_central
                ovn_create_topology
                ovn_start_clean_openvswitch
                ovn_set_ovs_config $ovn_ip $ovn_ip
                ip link set $BF_NIC up
                ovn_start_ovn_controller"

    if [ "$DPDK" == 1 ]; then
        on_bf_exec "config_simple_bridge_with_rep 0"
    fi

}

function config_bf_ovn_pf() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local tun_dev=$BF_NIC

    ovn_start_clean_openvswitch

    if [ "$DPDK" == 1 ]; then
        config_simple_bridge_with_rep 0
        tun_dev="br-phy"
        ip link set $tun_dev up
    fi

    ip addr add $ovn_controller_ip/24 dev $tun_dev
    ovn_config_mtu $BF_NIC

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_bf_ovn_pf_vlan() {
    local ovn_central_ip=$1
    local ovn_controller_ip=$2
    local port_extra_args=$(get_dpdk_pf_port_extra_args)

    ovn_start_clean_openvswitch
    ovs_create_bridge_vlan_interface
    ovs_add_port_to_switch $OVN_PF_BRIDGE $BF_NIC "$port_extra_args"

    ovn_config_mtu $BF_NIC $OVN_PF_BRIDGE $OVN_VLAN_INTERFACE
    ip addr add $ovn_controller_ip/24 dev $OVN_VLAN_INTERFACE
    ip link set $BF_NIC up

    ovn_set_ovs_config $ovn_central_ip $ovn_controller_ip
    ovn_start_ovn_controller
}

function config_bf_host_pf() {
    local bridge=$1

    if [ "$DPDK" == 1 ]; then
        ovs_add_port "ECPF" 0 $bridge $BF_PCI
    else
        ovs-vsctl add-port $bridge $BF_HOST_NIC
    fi

    ip link set $BF_HOST_NIC up
}

function __common_ovn_bf_test_init() {
    require_bf
    require_bf_ovn
}
