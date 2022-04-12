# OVN IPs
OVN_LOCAL_CENTRAL_IP="127.0.0.1"
OVN_CENTRAL_IP="192.168.100.100"
OVN_CENTRAL_IPV6="192:168:100::100"
OVN_REMOTE_CONTROLLER_IP="192.168.100.101"
OVN_REMOTE_CONTROLLER_IPV6="192:168:100::101"

OVN_TUNNEL_MTU=1700

OVN_PF_BRIDGE="br-pf"
OVN_VLAN_INTERFACE="vlan-int"
OVN_VLAN_TAG=100
PF_VLAN_INT="$NIC.$OVN_VLAN_TAG"
BOND_VLAN_INT="$OVN_BOND.$OVN_VLAN_TAG"

function __reset_nic() {
    local nic=${NIC:-}

    ip link set $nic down
    ip addr flush dev $nic
    ip link set $nic mtu 1500
}

function ovn_config_mtu() {
    local nic
    for nic in $@; do
        ip link set $nic mtu $OVN_TUNNEL_MTU
        ip link set $nic up
    done
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
