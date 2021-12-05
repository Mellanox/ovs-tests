OVN_BRIDGE_INT="br-int"
OVN_CTL="/usr/share/ovn/scripts/ovn-ctl"

# Tunnels
TUNNEL_GENEVE="geneve"

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
    if [[ -z "$result" ]]; then
        rules_count="0"
    fi

    if echo "$result" | grep "packets:0, bytes:0"; then
        err "packets:0, bytes:0"
        return 1
    elif (("$rules_count" == "$count")); then
        success "Found $count rules as expected"
        return 0
    fi

    err "Expected $count rules, found $rules_count"
    return 1
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

function check_and_print_ovs_offloaded_rules() {
    local traffic_filter=$1
    local rules_num=$2

    ovs_dump_offloaded_flows --names | grep "$traffic_filter"
    check_offloaded_rules $rules_num $traffic_filter
}

function check_traffic_offload() {
    local rep=$1
    local ns=$2
    local dst_ip=$3
    local traffic_type=$4

    local traffic_filter=$ETH_IP
    local tcpdump_filter="$traffic_type"
    local rules_num=2

    # VLAN traffic is chain rules
    # Sender side: vlan pop > redirect to port
    # Receiver side: redirect to port > push vlan
    if [[ -n "$HAS_VLAN" ]] && [[ "$traffic_type" == "icmp" || "$traffic_type" == "tcp" || "$traffic_type" == "udp" ]]; then
        rules_num=4
    fi

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
    tcpdump -Unnepi $rep $tcpdump_filter -c 3 &
    local tdpid=$!

    local tdpid_receiver=
    if [[ -z "$HAS_REMOTE" ]]; then
        tcpdump -Unnepi $REP2 $tcpdump_filter -c 3 >/dev/null 2>&1 &
        tdpid_receiver=$!
    else
        tdpid_receiver=$(on_remote "nohup tcpdump -Unnepi $rep $tcpdump_filter -c 3 > /dev/null 2>&1 & echo \$!")
    fi
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

    title "Check ${traffic_type^^} OVS offload rules on the sender"
    check_and_print_ovs_offloaded_rules $traffic_filter $rules_num

    if [[ -n "$HAS_REMOTE" ]]; then
        title "Check ${traffic_type^^} OVS offload rules on the receiver"
        on_remote_exec "check_and_print_ovs_offloaded_rules $traffic_filter $rules_num" && success || err
    fi

    # If tcpdump finished then it capture more than expected to be offloaded
    title "Check ${traffic_type^^} traffic is offloaded on the sender"
    [[ -d /proc/$tdpid ]] && success || err

    title "Check ${traffic_type^^} traffic is offloaded on the receiver"
    if [[ -z "$HAS_REMOTE" ]]; then
        [[ -d /proc/$tdpid_receiver ]] && success || err
    else
        on_remote "[[ -d /proc/$tdpid_receiver ]]" && success || err
    fi

    ovs_flush_rules
    killall -q tcpdump

    if [[ -n "$HAS_REMOTE" ]]; then
        on_remote_exec "ovs_flush_rules
                        killall -q tcpdump"
    fi
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

    local cmd=$(ns_wrap "timeout 10 iperf3 -s -D" $server_ns)
    eval $cmd
    sleep 0.5

    check_traffic_offload $rep $client_ns $server_ip tcp
    killall -q iperf3
}

function check_local_tcp6_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    local cmd=$(ns_wrap "timeout 10 iperf3 -6 -s -D" $server_ns)
    eval $cmd
    sleep 0.5

    check_traffic_offload $rep $client_ns $server_ip tcp6
    killall -q iperf3
}

function check_remote_tcp_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    local cmd=$(ns_wrap "timeout 15 iperf3 -s -D" $server_ns)
    on_remote "$cmd"
    sleep 0.5

    check_traffic_offload $rep $client_ns $server_ip tcp
    on_remote "killall -q iperf3"
}

function check_remote_tcp6_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    local cmd=$(ns_wrap "timeout 15 iperf3 -6 -s -D" $server_ns)
    on_remote "$cmd"
    sleep 0.5

    check_traffic_offload $rep $client_ns $server_ip tcp6
    on_remote "killall -q iperf3"
}

function check_local_udp_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    local cmd=$(ns_wrap "timeout 10 $OVN_DIR/udp-perf.py -s -D" $server_ns)
    eval $cmd
    sleep 0.5

    check_traffic_offload $rep $client_ns $server_ip udp
    killall -q udp-perf.py
}

function check_local_udp6_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    local cmd=$(ns_wrap "timeout 10 $OVN_DIR/udp-perf.py -6 -s -D" $server_ns)
    eval $cmd
    sleep 0.5

    check_traffic_offload $rep $client_ns $server_ip udp6
    killall -q udp-perf.py
}

function check_remote_udp_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    local cmd=$(ns_wrap "timeout 15 $OVN_DIR/udp-perf.py -s -D" $server_ns)
    on_remote "$cmd"
    sleep 0.5

    check_traffic_offload $rep $client_ns $server_ip udp
    on_remote "killall -q udp-perf.py"
}

function check_remote_udp6_traffic_offload() {
    local rep=$1
    local client_ns=$2
    local server_ns=$3
    local server_ip=$4

    local cmd=$(ns_wrap "timeout 15 $OVN_DIR/udp-perf.py -6 -s -D" $server_ns)
    on_remote "$cmd"
    sleep 0.5

    check_traffic_offload $rep $client_ns $server_ip udp6
    on_remote "killall -q udp-perf.py"
}

function check_fragmented_traffic() {
    local rep=$1
    local ns=$2
    local dst_ip=$3
    local size=$4
    local is_ipv6=$5

    local traffic_filter=$ETH_IP
    local rules_filter=ip
    local tcpdump_filter=icmp

    if [[ -n "$is_ipv6" ]]; then
        traffic_filter=$ETH_IP6
        rules_filter=ipv6
        tcpdump_filter=$TCPDUMP_IGNORE_IPV6_NEIGH
    fi

    # Listen to traffic on representor
    timeout 10 tcpdump -Unnepi $rep $tcpdump_filter -c 8 &
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
    ovs_dump_offloaded_flows --names
    check_offloaded_rules 0 $traffic_filter

    echo "All OVS flow rules"
    ovs_dump_flows --names type=all filter="$rules_filter"
    check_fragmented_rules $traffic_filter

    title "Check captured packets count"
    # Wait tcpdump to finish and verify traffic is not offloaded
    verify_have_traffic $tdpid

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

function ovs_flush_rules() {
    ovs-vsctl set O . other_config:max-idle=1
    sleep 0.5
    ovs-vsctl remove O . other_config max-idle
}

function ovs_create_bridge_vlan_interface() {
    local br=${1:-$OVN_PF_BRIDGE}
    local interface=${2:-$OVN_VLAN_INTERFACE}
    local vlan=${3:-$OVN_VLAN_TAG}

    ovs-vsctl --may-exist add-br $br -- --may-exist add-port $br $interface tag=$vlan -- set Interface $interface type=internal
}

function ovn_clear_switches() {
    ovn-nbctl -f csv --columns=name list LOGICAL_SWITCH | xargs -L 1 ovn-nbctl ls-del &>/dev/null
}

function ovn_clear_routers() {
    ovn-nbctl -f csv --columns=name list LOGICAL_ROUTER | xargs -L 1 ovn-nbctl lr-del &>/dev/null
}

function ovn_clear_chassis() {
    ovn-sbctl -f csv --columns=name list CHASSIS | xargs -L 1 ovn-sbctl chassis-del &>/dev/null
}

function ovn_start_clean() {
    $OVN_CTL restart_northd >/dev/null
    ovn_clear_switches
    ovn_clear_routers
    ovn_clear_chassis
}

function ovn_add_network() {
    local br=${1:-$OVN_PF_BRIDGE}
    local network_iface=${2:-$NIC}
    local network=${3:-$OVN_EXTERNAL_NETWORK}

    ovs-vsctl --may-exist add-br $br -- --may-exist add-port $br $network_iface -- set Open_vSwitch . external_ids:ovn-bridge-mappings=$network:$br
}

function ovn_remove_network() {
    local br=${1:-$OVN_PF_BRIDGE}
    local network_iface=${2:-$NIC}

    ovs-vsctl --if-exists del-port $br $network_iface -- --if-exists del-br $br -- remove Open_vSwitch . external_ids ovn-bridge-mappings
}
