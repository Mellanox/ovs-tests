OVN_BRIDGE_INT="br-int"
OVN_CTL="/usr/share/ovn/scripts/ovn-ctl"
OVN_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" &>/dev/null && pwd)

# Topologies
OVN_TOPO_DIR="$OVN_DIR/ovn-topologies"
TOPOLOGY_SINGLE_SWITCH="$OVN_TOPO_DIR/single-switch.yaml"
TOPOLOGY_2_SWITCHES="$OVN_TOPO_DIR/two-switches.yaml"
TOPOLOGY_SINGLE_ROUTER_2_SWITCHES="$OVN_TOPO_DIR/single-router-2-switches.yaml"

# Tunnels
TUNNEL_GENEVE="geneve"

# OVN IPs
OVN_LOCAL_CENTRAL_IP="127.0.0.1"
OVN_CENTRAL_IP="192.168.100.100"
OVN_REMOTE_CONTROLLER_IP="192.168.100.101"

# Traffic type
ETH_IP="0x0800"
ETH_IP6="0x86dd"

OVN_BOND="bond0"

# Traffic Filters
# Ignore IPv6 Neighbor-Advertisement, Neighbor Solicitation and Router Solicitation packets
TCPDUMP_IGNORE_IPV6_NEIGH="icmp6 and ip6[40] != 133 and ip6[40] != 135 and ip6[40] != 136"

function require_ovn() {
    [ ! -e "${OVN_CTL}" ] && fail "Missing $OVN_CTL"
}

function ovn_start_northd_central() {
    local ip=${1:-$OVN_LOCAL_CENTRAL_IP}

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
    local ovn_remote_ip=${1:-$OVN_LOCAL_CENTRAL_IP}
    local encap_ip=${2:-$OVN_LOCAL_CENTRAL_IP}
    local encap_type=${3:-$TUNNEL_GENEVE}

    ovs-vsctl set open . external-ids:ovn-remote=tcp:$ovn_remote_ip:6642
    ovs-vsctl set open . external-ids:ovn-encap-ip=$encap_ip
    ovs-vsctl set open . external-ids:ovn-encap-type=$encap_type
}

function ovn_remove_ovs_config() {
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

function check_rules() {
    local count=$1
    local traffic_filter=$2
    local rules_type=$3
    local frag_filter=$4 #optional

    local result=$(ovs-appctl dpctl/dump-flows type=$rules_type 2>/dev/null | grep $traffic_filter | grep -E "$frag_filter" | grep -v drop)
    local rules_count=$(echo "$result" | wc -l)

    if [[ $count == "0" ]]; then
        if [[ -z "$result" ]]; then
            success "Found 0 rules as expected"
        else
            err "Expected 0 rules, found $rules_count"
        fi
        return
    fi

    if echo "$result" | grep "packets:0, bytes:0"; then
        err "packets:0, bytes:0"
        return
    fi

    if (("$rules_count" == "$count")); then
        success "Found $count rules as expected"
    else
        err "Expected $count rules, found $rules_count"
    fi
}

function check_offloaded_rules() {
    local count=$1
    local traffic_filter=$2

    check_rules $count $traffic_filter "offloaded"
}

function check_fragmented_rules() {
    local traffic_filter=$1

    check_rules 4 $traffic_filter "all" "frag=(first|later)"
}

function check_traffic_offload() {
    local rep=$1
    local ns=$2
    local dst_ip=$3
    local traffic_type=$4
    local tcpdump_file=/tmp/$$.pcap

    local traffic_filter=$ETH_IP
    local tcpdump_filter="$traffic_type"

    if [[ "$traffic_type" == "icmp6" ]]; then
        tcpdump_filter=$TCPDUMP_IGNORE_IPV6_NEIGH
        traffic_filter=$ETH_IP6
    elif [[ "$traffic_type" == "tcp6" ]]; then
        tcpdump_filter="ip6 proto 6"
        traffic_filter="$ETH_IP6.*proto=6"
    elif [[ "$traffic_type" == "udp6" ]]; then
        tcpdump_filter="ip6 proto 17"
        traffic_filter="$ETH_IP6.*proto=17"
    fi

    # Listen to traffic on representor
    timeout 15 tcpdump -Unnepi $rep $tcpdump_filter -c 8 -w $tcpdump_file &
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
    elif [[ $traffic_type == "udp" ]]; then
        ip netns exec $ns timeout 10 $OVN_DIR/udp-perf.py -c $dst_ip --pass-rate 0.7 && success || err
    elif [[ $traffic_type == "udp6" ]]; then
        ip netns exec $ns timeout 10 $OVN_DIR/udp-perf.py -6 -c $dst_ip --pass-rate 0.7 && success || err
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
    ovs_flush_rules
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
    sleep 0.5

    check_traffic_offload $rep $client_ns $server_ip tcp
    killall -q iperf3
}

function check_local_tcp6_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    ip netns exec $server_ns timeout 10 iperf3 -6 -s >/dev/null 2>&1 &
    sleep 0.5

    check_traffic_offload $rep $client_ns $server_ip tcp6
    killall -q iperf3
}

function check_remote_tcp_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    on_remote "ip netns exec $server_ns timeout 15 iperf3 -s >/dev/null 2>&1" &
    sleep 2

    check_traffic_offload $rep $client_ns $server_ip tcp
    on_remote "killall -q iperf3"
}

function check_remote_tcp6_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    on_remote "ip netns exec $server_ns timeout 15 iperf3 -6 -s >/dev/null 2>&1" &
    sleep 2

    check_traffic_offload $rep $client_ns $server_ip tcp6
    on_remote "killall -q iperf3"
}

function check_local_udp_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    ip netns exec $server_ns timeout 10 $OVN_DIR/udp-perf.py -s &
    sleep 0.5

    check_traffic_offload $rep $client_ns $server_ip udp
    killall -q udp-perf.py
}

function check_local_udp6_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    ip netns exec $server_ns timeout 10 $OVN_DIR/udp-perf.py -6 -s &
    sleep 0.5

    check_traffic_offload $rep $client_ns $server_ip udp6
    killall -q udp-perf.py
}

function check_remote_udp_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    on_remote_exec "ip netns exec $server_ns timeout 15 $OVN_DIR/udp-perf.py -s" &
    sleep 2

    check_traffic_offload $rep $client_ns $server_ip udp
    on_remote "killall -q udp-perf.py"
}

function check_remote_udp6_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    on_remote_exec "ip netns exec $server_ns timeout 15 $OVN_DIR/udp-perf.py -6 -s" &
    sleep 2

    check_traffic_offload $rep $client_ns $server_ip udp6
    on_remote "killall -q udp-perf.py"
}

function check_fragmented_traffic() {
    local rep=$1
    local ns=$2
    local dst_ip=$3
    local size=$4
    local is_ipv6=$5

    local tcpdump_file=/tmp/$$.pcap
    local traffic_filter=$ETH_IP
    local rules_filter=ip
    local tcpdump_filter=icmp

    if [[ -n "$is_ipv6" ]]; then
        traffic_filter=$ETH_IP6
        rules_filter=ipv6
        tcpdump_filter=$TCPDUMP_IGNORE_IPV6_NEIGH
    fi

    # Listen to traffic on representor
    timeout 15 tcpdump -Unnepi $rep $tcpdump_filter -w $tcpdump_file &
    sleep 0.5

    title "Check sending traffic"
    if [[ -z "$is_ipv6" ]]; then
        ip netns exec $ns ping -s $size -w 4 $dst_ip && success || err
    else
        ip netns exec $ns ping -6 -s $size -w 4 $dst_ip && success || err
    fi

    title "Check OVS Rules"
    # Fragmented traffic should not be offloaded
    echo "OVS offloaded flow rules"
    ovs_dump_flows type=offloaded
    check_offloaded_rules 0 $traffic_filter

    echo "All OVS flow rules"
    ovs_dump_flows type=all filter="$rules_filter"
    check_fragmented_rules $traffic_filter

    title "Check captured packets count"
    # Stop tcpdump
    killall -q tcpdump
    sleep 1

    # Ensure more than 2 packets appear
    local count=$(tcpdump -nnr $tcpdump_file | wc -l)
    if [[ $count -le "2" ]]; then
        err "Fragmented packets count is not as expected, expected > '2', found '$count'"
        tcpdump -nnr $tcpdump_file
    else
        success
    fi

    rm -f $tcpdump_file
    ovs_flush_rules
}

function check_fragmented_ipv4_traffic() {
    local rep=$1
    local ns=$2
    local dst_ip=$3
    local size=$4

    check_fragmented_traffic $rep $ns $dst_ip $size
}

function check_fragmented_ipv6_traffic() {
    local rep=$1
    local ns=$2
    local dst_ip=$3
    local size=$4

    check_fragmented_traffic $rep $ns $dst_ip $size true
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

function ovs_flush_rules() {
    ovs-vsctl set O . other_config:max-idle=1
    sleep 0.5
    ovs-vsctl remove O . other_config max-idle
}
