OVN_BRIDGE_INT="br-int"
OVN_SYSTEM_ID=$(hostname)
OVN_CTL="/usr/share/ovn/scripts/ovn-ctl"
OVN_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" &>/dev/null && pwd)

# Topologies
TOPOLOGY_SINGLE_SWITCH="$OVN_DIR/ovn-topologies/ovn-single-switch-topology.yaml"

# Tunnels
TUNNEL_GENEVE="geneve"

# OVN IPs
OVN_LOCAL_CENTRAL_IP="127.0.0.1"
OVN_CENTRAL_IP="192.168.100.100"
OVN_REMOTE_CONTROLLER_IP="192.168.100.101"

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
    ovs-vsctl set O . other_config:max-idle=2000
}

function ovn_remove_ovs_config() {
    ovs-vsctl remove open . external-ids system-id
    ovs-vsctl remove open . external-ids ovn-remote
    ovs-vsctl remove open . external-ids ovn-encap-ip
    ovs-vsctl remove open . external-ids ovn-encap-type
    ovs-vsctl remove O . other_config max-idle
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

function check_offloaded_rules() {
    local count=$1
    local traffic_filter=$2

    local result=$(ovs-appctl dpctl/dump-flows type=offloaded 2>/dev/null | grep $traffic_filter | grep -v drop)

    if echo "$result" | grep "packets:0, bytes:0"; then
        err "packets:0, bytes:0"
        return
    fi

    local rules_count=$(echo "$result" | wc -l)
    if (("$rules_count" == "$count")); then
        success
    else
        err
    fi
}

function check_traffic_offload() {
    local rep=$1
    local ns=$2
    local dst_ip=$3
    local traffic_type=$4
    local tcpdump_file=/tmp/$$.pcap

    local traffic_filter="0x0800"
    local tcpdump_filter="$traffic_type"

    if [[ "$traffic_type" == "icmp6" ]]; then
        # Ignore IPv6 Neighbor-Advertisement and Neighbor Solicitation packets
        tcpdump_filter="icmp6 and ip6[40] != 136 and ip6[40] != 135"
        traffic_filter="0x86dd"
    elif [[ "$traffic_type" == "tcp6" ]]; then
        tcpdump_filter="ip6 proto 6"
        traffic_filter="0x86dd"
    fi

    # Listen to traffic on representor
    timeout 15 tcpdump -nnepi $rep $tcpdump_filter -c 8 -w $tcpdump_file &
    local tdpid=$!
    sleep 0.5

    # Traffic between VFs
    title "Check sending ${traffic_type^^} traffic"
    if [[ $traffic_type == "icmp" ]]; then
        ip netns exec $ns ping -w 4 $dst_ip && success || err
    elif [[ $traffic_type == "icmp6" ]]; then
        ip netns exec $ns ping -6 -w 4 $dst_ip && success || err
    elif [[ $traffic_type == "tcp" ]]; then
        ip netns exec $ns timeout 15 iperf3 -t 5 -c $dst_ip && success || err
    elif [[ $traffic_type == "tcp6" ]]; then
        ip netns exec $ns timeout 15 iperf3 -6 -t 5 -c $dst_ip && success || err
        traffic_filter="0x86dd"
    else
        fail "Unknown traffic $traffic_type"
    fi

    title "Check ${traffic_type^^} OVS offload rules"
    ovs_dump_flows type=offloaded
    check_offloaded_rules 2 $traffic_filter

    # Rules should appear, request and reply
    title "Check ${traffic_type^^} traffic is offloaded"
    # Stop tcpdump
    kill $tdpid 2>/dev/null
    sleep 1

    # Ensure first packets appeared
    local count=$(tcpdump -nnr $tcpdump_file | wc -l)
    if [[ $count != "2" ]]; then
        err "No offload"
        tcpdump -nnr $tcpdump_file
    else
        success
    fi

    rm -f $tcpdump_file
}

function check_icmp_traffic_offload() {
    local rep=$1
    local ns=$2
    local dst_ip=$3

    check_traffic_offload $rep $ns $dst_ip icmp
}

function check_icmp6_traffic_offload() {
    local rep=$1
    local ns=$2
    local dst_ip=$3

    check_traffic_offload $rep $ns $dst_ip icmp6
}

function check_local_tcp_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    ip netns exec $server_ns timeout 10 iperf3 -s >/dev/null 2>&1 &

    check_traffic_offload $rep $client_ns $server_ip tcp
    killall iperf3 2>/dev/null
}

function check_local_tcp6_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    ip netns exec $server_ns timeout 10 iperf3 -6 -s >/dev/null 2>&1 &

    check_traffic_offload $rep $client_ns $server_ip tcp6
    killall iperf3 2>/dev/null
}

function check_remote_tcp_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    on_remote "ip netns exec $server_ns timeout 15 iperf3 -s >/dev/null 2>&1" &
    sleep 2

    check_traffic_offload $rep $client_ns $server_ip tcp
    on_remote "killall iperf3"
}

function ovn_create_topology() {
    local topology_file=$1

    $OVN_DIR/ovn-topology-creator.py -f "$topology_file" -c
    ovn-nbctl show
}

function ovn_destroy_topology() {
    local topology_file=$1

    $OVN_DIR/ovn-topology-creator.py -f "$topology_file" -d
}
