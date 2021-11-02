OVN_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" &>/dev/null && pwd)

. $OVN_DIR/../common.sh
. $OVN_DIR/common-ovn.sh
. $OVN_DIR/common-ovn-topology.sh

# OVN IPs
OVN_LOCAL_CENTRAL_IP="127.0.0.1"
OVN_CENTRAL_IP="192.168.100.100"
OVN_REMOTE_CONTROLLER_IP="192.168.100.101"

# Test Config
TOPOLOGY=
HAS_REMOTE=
HAS_BOND=

function __ovn_clean_up() {
    ovn_stop_ovn_controller
    ovn_destroy_topology
    ovn_stop_northd_central
    ovn_remove_ovs_config
    ovs_clear_bridges

    ip addr flush dev $NIC
    ip link set $NIC mtu 1500
    ip -all netns del
    unbind_vfs

    if [[ -n "$HAS_BOND" ]]; then
        unbind_vfs $NIC2
        clear_bonding
        disable_sriov_port2
    fi

    bind_vfs
}

function ovn_clean_up() {
    __ovn_clean_up

    if [[ -n "$HAS_REMOTE" ]]; then
        on_remote_exec "__ovn_clean_up"
    fi
}

require_ovn
