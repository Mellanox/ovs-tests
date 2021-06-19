OVN_BRIDGE_INT="br-int"
OVN_SYSTEM_ID=$(hostname)
OVN_CTL="/usr/share/ovn/scripts/ovn-ctl"

function require_ovn() {
    [ ! -e "${OVN_CTL}" ] && fail "Missing $OVN_CTL"
}

function ovn_start_northd_central() {
    local ip=$1

    $OVN_CTL start_northd
    ovn-nbctl set-connection ptcp:6641:$ip
    ovn-sbctl set-connection ptcp:6642:$ip
}

function ovn_stop_northd_central() {
    $OVN_CTL stop_northd
}

function ovn_start_ovn_controller() {
    $OVN_CTL start_controller
}

function ovn_stop_ovn_controller() {
    $OVN_CTL stop_controller
}

function ovn_set_ovs_config() {
    local system_id=$1
    local ovn_remote_ip=$2
    local encap_ip=$3
    local encap_type=$4

    ovs-vsctl set open . external-ids:system-id=$system_id
    ovs-vsctl set open . external-ids:ovn-remote=tcp:$ovn_remote_ip:6642
    ovs-vsctl set open . external-ids:ovn-encap-ip=$encap_ip
    ovs-vsctl set open . external-ids:ovn-encap-type=$encap_type
}

function ovn_remove_ovs_config() {
    ovs-vsctl remove open . external-ids system-id
    ovs-vsctl remove open . external-ids ovn-remote
    ovs-vsctl remove open . external-ids ovn-encap-ip
    ovs-vsctl remove open . external-ids ovn-encap-type
}

function ovn_add_switch() {
    local switch=$1

    ovn-nbctl ls-add $switch
}

function ovn_add_port_to_switch() {
    local switch=$1
    local port=$2

    ovn-nbctl lsp-add $switch $port
}

function ovn_set_switch_port_addresses() {
    local port=$1
    local mac=$2
    # IP is optional
    local ip=$3

    ovn-nbctl lsp-set-addresses $port "$mac $ip"
}

function ovn_delete_switch_port() {
    local port=$1

    ovn-nbctl lsp-del $port
}

function ovn_delete_switch() {
    local switch=$1
    ovn-nbctl ls-del $switch
}

function ovs_add_port_to_switch() {
    local br=$1
    local port=$2

    ovs-vsctl add-port $br $port
}

function ovn_bind_ovs_port() {
    local ovs_port=$1
    local ovn_port=$2

    ovs-vsctl set Interface $ovs_port external_ids:iface-id=$ovn_port
}
