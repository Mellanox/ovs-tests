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

declare -A TRAFFIC_INFO=(
    ['offloaded_traffic_timeout']=15
    ['offloaded_traffic_verification_delay']=5
    ['offloaded_traffic_time_window']=3
    ['non_offloaded_traffic_timeout']=5
    ['non_offloaded_packets']=30
    ['client_ns']=ns0
    ['client_vf']=$VF
    ['client_rep']=$REP
    ['client_rule_fields']=""
    ['client_verify_offload']=1
    ['server_ns']=ns1
    ['server_vf']=$VF2
    ['server_rep']=$REP2
    ['server_rule_fields']=""
    ['server_verify_offload']=1
    ['skip_offload']=""
    ['local_traffic']=""
    ['bf_traffic']=""
)

function require_ovn() {
    [ ! -e "${OVN_CTL}" ] && fail "Missing $OVN_CTL"
}

function ovn_is_northd_central_running() {
    $OVN_CTL status_northd >/dev/null
}

function ovn_start_northd_central() {
    local ip=${1:-$OVN_LOCAL_CENTRAL_IP}

    ovn_is_northd_central_running || $OVN_CTL start_northd

    ovn-nbctl set-connection ptcp:6641:[$ip]
    ovn-sbctl set-connection ptcp:6642:[$ip]
}

function ovn_stop_northd_central() {
    ovn_is_northd_central_running && $OVN_CTL stop_northd
}

function ovn_is_controller_running() {
    $OVN_CTL status_controller >/dev/null
}

function verify_ovn_bridge() {
    for _ in $(seq 1 10); do
        sleep 1
        ovs-vsctl list-br | grep -q $OVN_BRIDGE_INT && return 0
    done

    fail "$OVN_BRIDGE_INT not created after 10 seconds"
}

function ovn_start_ovn_controller() {
    ovn_is_controller_running || $OVN_CTL start_controller
    verify_ovn_bridge
}

function ovn_stop_ovn_controller() {
    ovn_is_controller_running && $OVN_CTL stop_controller
}

function ovn_set_ovs_config() {
    local ovn_remote_ip=${1:-$OVN_LOCAL_CENTRAL_IP}
    local encap_ip=${2:-$OVN_LOCAL_CENTRAL_IP}
    local encap_type=${3:-$TUNNEL_GENEVE}

    ovs-vsctl set open . external-ids:ovn-remote=tcp:[$ovn_remote_ip]:6642
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

function ovn_bind_port() {
    local port=$1
    local ovn_port=$2

    ovs-vsctl --may-exist add-port $OVN_BRIDGE_INT $port -- set Interface $port external_ids:iface-id=$ovn_port
}

function check_rules() {
    local rule_fields=$1
    local rules_type=${2:-"all"}

    local traffic_rules=$(ovs-appctl dpctl/dump-flows --names type=$rules_type 2>/dev/null | grep -vE "(dst=33:33|drop|packets:0)")
    for rule_field in $rule_fields; do
        title "- Verifying rule $rule_field"
        local result=$(echo "$traffic_rules" | grep -i "$rule_field")

        if [[ "$result" == "" ]]; then
            err "Rule $rule_field not found"
            return 1
        fi
    done

    success "Found expected rules"
    return 0
}

function check_fragmented_rules() {
    local traffic_filter=$1
    local expected_count=${2:-4}

    local fragmented_flow_rules=$(ovs_dump_flows --names | grep -E "frag=(first|later)" | grep $traffic_filter | grep -vE "(drop|packets:0)")
    local rules_count=$(echo "$fragmented_flow_rules" | wc -l)
    if (("$rules_count" != "$expected_count")); then
        err "Expected 4 rules, found $rules_count"
        echo "$fragmented_flow_rules"
        return 1
    fi

    success "Found expected $expected_count flow rules"
    return 0
}

function check_and_print_ovs_offloaded_rules() {
    local rule_fields=$1

    ovs_dump_offloaded_flows --names
    check_rules "$rule_fields" "offloaded"
}

function send_background_traffic() {
    local traffic_type=$1
    local ns=$2
    local dst_ip=$3
    local timeout=$4
    local logfile=$5

    if [[ $traffic_type == "icmp" ]]; then
        ip netns exec $ns ping -w $timeout -i 0.1 $dst_ip >$logfile &
    elif [[ $traffic_type == "icmp6" ]]; then
        ip netns exec $ns ping -6 -w $timeout -i 0.1 $dst_ip >$logfile &
    elif [[ $traffic_type == "tcp" ]]; then
        ip netns exec $ns iperf3 -t $timeout -c $dst_ip --logfile $logfile &
    elif [[ $traffic_type == "tcp6" ]]; then
        ip netns exec $ns iperf3 -6 -t $timeout -c $dst_ip --logfile $logfile &
    elif [[ $traffic_type == "udp" ]]; then
        local packets=$((timeout * 10))
        ip netns exec $ns $OVN_DIR/udp-perf.py -c $dst_ip --packets $packets --pass-rate 0.7 --logfile $logfile &
    elif [[ $traffic_type == "udp6" ]]; then
        local packets=$((timeout * 10))
        ip netns exec $ns $OVN_DIR/udp-perf.py -6 -c $dst_ip --packets $packets --pass-rate 0.7 --logfile $logfile &
    else
        fail "Unknown traffic $traffic_type"
    fi
}

function __tcpdump_filter() {
    local traffic_type=$1

    local tcpdump_filter="$traffic_type"
    if [[ "$traffic_type" == "icmp6" ]]; then
        tcpdump_filter=$TCPDUMP_IGNORE_IPV6_NEIGH
    elif [[ "$traffic_type" == "tcp6" ]]; then
        tcpdump_filter="ip6 proto 6"
    elif [[ "$traffic_type" == "udp6" ]]; then
        tcpdump_filter="ip6 proto 17"
    fi

    echo $tcpdump_filter
}

function __verify_client_rules() {
    local client_rule_fields=$1
    local bf_traffic=${TRAFFIC_INFO['bf_traffic']}

    if [[ -z $bf_traffic ]]; then
        check_and_print_ovs_offloaded_rules "$client_rule_fields"
    else
        on_bf_exec "check_and_print_ovs_offloaded_rules \"$client_rule_fields\""
    fi
}

function __verify_server_rules() {
    local server_rule_fields=$1
    local bf_traffic=${TRAFFIC_INFO['bf_traffic']}

    if [[ -z $bf_traffic ]]; then
        on_remote_exec "check_and_print_ovs_offloaded_rules \"$server_rule_fields\"" && success || err
    else
        on_remote_bf_exec "check_and_print_ovs_offloaded_rules \"$server_rule_fields\"" && success || err
    fi
}

function __start_tcpdump_local() {
    local rep=$1
    local tcpdump_filter=$2
    local non_offloaded_packets=$3

    local tdpid=
    local bf_traffic=${TRAFFIC_INFO['bf_traffic']}
    if [[ -z "$bf_traffic" ]]; then
        tcpdump -Unnepi $rep $tcpdump_filter -c $non_offloaded_packets >/dev/null &
        tdpid=$!
    else
        tdpid=$(on_bf "nohup tcpdump -Unnepi $rep $tcpdump_filter -c $non_offloaded_packets >/dev/null 2>&1 & echo \$!")
    fi

    echo $tdpid
}

function __start_tcpdump() {
    local rep=$1
    local tcpdump_filter=$2
    local non_offloaded_packets=$3

    local tdpid=
    local local_traffic=${TRAFFIC_INFO['local_traffic']}
    local bf_traffic=${TRAFFIC_INFO['bf_traffic']}
    if [[ -n "$local_traffic" ]]; then
        tdpid=$(__start_tcpdump_local $rep "$tcpdump_filter" $non_offloaded_packets)
    elif [[ -z "$bf_traffic" ]]; then
        tdpid=$(on_remote "nohup tcpdump -Unnepi $rep $tcpdump_filter -c $non_offloaded_packets >/dev/null 2>&1 & echo \$!")
    else
        tdpid=$(on_remote_bf "nohup tcpdump -Unnepi $rep $tcpdump_filter -c $non_offloaded_packets >/dev/null 2>&1 & echo \$!")
    fi

    echo $tdpid
}

function __verify_tcpdump_offload_local() {
    local tdpid=$1
    local bf_traffic=${TRAFFIC_INFO['bf_traffic']}

    if [[ -z "$bf_traffic" ]]; then
        [[ -d /proc/$tdpid ]] && success || err
        killall -q tcpdump
    else
        on_bf "[[ -d /proc/$tdpid ]]" && success || err
        on_bf "killall -q tcpdump"
    fi
}

function __verify_tcpdump_offload() {
    local tdpid=$1

    local local_traffic=${TRAFFIC_INFO['local_traffic']}
    local bf_traffic=${TRAFFIC_INFO['bf_traffic']}

    if [[ -n "$local_traffic" ]]; then
        __verify_tcpdump_offload_local $tdpid
    else
        if [[ -z "$bf_traffic" ]]; then
            on_remote "[[ -d /proc/$tdpid ]]" && success || err
            on_remote "killall -9 tcpdump"
        else
            on_remote_bf "[[ -d /proc/$tdpid ]]" && success || err
            on_remote_bf "killall -9 tcpdump"
        fi
    fi
}

function check_traffic_offload() {
    local server_ip=$1
    local traffic_type=$2

    local client_ns=${TRAFFIC_INFO['client_ns']}
    local client_rep=${TRAFFIC_INFO['client_rep']}
    local client_rule_fields=${TRAFFIC_INFO['client_rule_fields']}
    local client_verify_offload=${TRAFFIC_INFO['client_verify_offload']}

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local server_rep=${TRAFFIC_INFO['server_rep']}
    local server_rule_fields=${TRAFFIC_INFO['server_rule_fields']}
    local server_verify_offload=${TRAFFIC_INFO['server_verify_offload']}

    local non_offloaded_packets=${TRAFFIC_INFO['non_offloaded_packets']}
    local skip_offload=${TRAFFIC_INFO['skip_offload']}
    local local_traffic=${TRAFFIC_INFO['local_traffic']}
    local bf_traffic=${TRAFFIC_INFO['bf_traffic']}
    local tcpdump_filter=$(__tcpdump_filter $traffic_type)

    if [[ -z $client_verify_offload ]] && [[ -z $server_verify_offload ]]; then
        skip_offload=1
    fi

    # Send background traffic before capturing traffic
    title "Sending ${traffic_type^^} traffic"
    local logfile=$(mktemp)
    local traffic_timeout=${TRAFFIC_INFO['offloaded_traffic_timeout']}
    if [[ -n "$skip_offload" ]]; then
        traffic_timeout=${TRAFFIC_INFO['non_offloaded_traffic_timeout']}
    fi

    send_background_traffic $traffic_type $client_ns $server_ip $traffic_timeout $logfile
    local traffic_pid=$!
    timeout 5 tail -f $logfile | head -n 5 &

    if [[ -n "$skip_offload" ]]; then
        wait $traffic_pid && success || err
        ovs_flush_rules
        rm -f $logfile
        return
    fi

    tmp=${TRAFFIC_INFO['offloaded_traffic_verification_delay']}
    echo "Sleep for $tmp seconds initial traffic"
    sleep $tmp

    if [[ -n $client_verify_offload ]]; then
        echo "Start client tcpdump"
        local tdpid=$(__start_tcpdump_local $client_rep "$tcpdump_filter" $non_offloaded_packets)
    fi

    if [[ -n $server_verify_offload ]]; then
        echo "Start server tcpdump"
        local tdpid_receiver=$(__start_tcpdump $server_rep "$tcpdump_filter" $non_offloaded_packets)
    fi

    if [[ -n $client_rule_fields ]]; then
        title "Check ${traffic_type^^} OVS offload rules on the sender"
        __verify_client_rules "$client_rule_fields"
    fi

    if [[ -z "$local_traffic" ]] && [[ -n $server_rule_fields ]]; then
        title "Check ${traffic_type^^} OVS offload rules on the receiver"
        __verify_server_rules "$server_rule_fields"
    fi

    # If tcpdump finished then it capture more than expected to be offloaded
    sleep "${TRAFFIC_INFO['offloaded_traffic_time_window']}"

    if [[ -n $client_verify_offload ]]; then
        title "Check ${traffic_type^^} traffic is offloaded on the sender"
        __verify_tcpdump_offload_local $tdpid
    fi

    if [[ -n $server_verify_offload ]]; then
        title "Check ${traffic_type^^} traffic is offloaded on the receiver"
        __verify_tcpdump_offload $tdpid_receiver
    fi

    title "Wait ${traffic_type^^} traffic"
    wait $traffic_pid && success || err
    rm -f $logfile

    if [[ -z "$bf_traffic" ]]; then
        ovs_flush_rules
        if [[ -z "$local_traffic" ]]; then
            on_remote_exec "ovs_flush_rules"
        fi
    else
        on_bf_exec "ovs_flush_rules"
        if [[ -z "$local_traffic" ]]; then
            on_remote_bf_exec "ovs_flush_rules"
        fi
    fi
}

function check_icmp_traffic_offload() {
    local dst_ip=$1

    check_traffic_offload $dst_ip icmp
}

function check_icmp6_traffic_offload() {
    local dst_ip=$1

    check_traffic_offload $dst_ip icmp6
}

function check_local_tcp_traffic_offload() {
    local server_ip=$1

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local cmd=$(ns_wrap "timeout 10 iperf3 -s -D" $server_ns)
    eval $cmd
    sleep 0.5

    check_traffic_offload $server_ip tcp
    killall -q iperf3
}

function check_local_tcp6_traffic_offload() {
    local server_ip=$1

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local cmd=$(ns_wrap "timeout 10 iperf3 -6 -s -D" $server_ns)
    eval $cmd
    sleep 0.5

    check_traffic_offload $server_ip tcp6
    killall -q iperf3
}

function check_remote_tcp_traffic_offload() {
    local server_ip=$1

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local cmd=$(ns_wrap "timeout 15 iperf3 -s -D" $server_ns)
    on_remote "$cmd"
    sleep 0.5

    check_traffic_offload $server_ip tcp
    on_remote "killall -q iperf3"
}

function check_remote_tcp6_traffic_offload() {
    local server_ip=$1

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local cmd=$(ns_wrap "timeout 15 iperf3 -6 -s -D" $server_ns)
    on_remote "$cmd"
    sleep 0.5

    check_traffic_offload $server_ip tcp6
    on_remote "killall -q iperf3"
}

function check_local_udp_traffic_offload() {
    local server_ip=$1

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local cmd=$(ns_wrap "timeout 10 $OVN_DIR/udp-perf.py -s -D" $server_ns)
    eval $cmd
    sleep 0.5

    check_traffic_offload $server_ip udp
    killall -q udp-perf.py
}

function check_local_udp6_traffic_offload() {
    local server_ip=$1

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local cmd=$(ns_wrap "timeout 10 $OVN_DIR/udp-perf.py -6 -s -D" $server_ns)
    eval $cmd
    sleep 0.5

    check_traffic_offload $server_ip udp6
    killall -q udp-perf.py
}

function check_remote_udp_traffic_offload() {
    local server_ip=$1

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local cmd=$(ns_wrap "timeout 15 $OVN_DIR/udp-perf.py -s -D" $server_ns)
    on_remote "$cmd"
    sleep 0.5

    check_traffic_offload $server_ip udp
    on_remote "killall -q udp-perf.py"
}

function check_remote_udp6_traffic_offload() {
    local server_ip=$1

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local cmd=$(ns_wrap "timeout 15 $OVN_DIR/udp-perf.py -6 -s -D" $server_ns)
    on_remote "$cmd"
    sleep 0.5

    check_traffic_offload $server_ip udp6
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
    local tdpid=$!
    sleep 0.5

    title "Check sending traffic"
    if [[ -z "$is_ipv6" ]]; then
        ip netns exec $ns ping -s $size -w 4 $dst_ip && success || err
    else
        ip netns exec $ns ping -6 -s $size -w 4 $dst_ip && success || err
    fi

    title "Check OVS Rules"
    # Offloading fragmented traffic is not supported
    ovs_dump_flows --names filter="$rules_filter"
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
    local max_idle=$(ovs-vsctl get Open_vSwitch . other_config:max-idle 2>/dev/null)

    ovs_conf_set max-idle 1
    sleep 0.5

    if [[ -n $max_idle ]]; then
        ovs_conf_set max-idle $max_idle
    else
        ovs_conf_remove max-idle
    fi
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

function ovn_clear_load_balancers() {
    ovn-nbctl -f csv --columns=name list LOAD_BALANCER | xargs -L 1 ovn-nbctl lb-del &>/dev/null
}

function ovn_start_clean() {
    $OVN_CTL restart_northd >/dev/null
    ovn_clear_switches
    ovn_clear_routers
    ovn_clear_load_balancers
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

function ovn_lsp_set_tag() {
    local port=$1
    local tag=$2

    ovn-nbctl set LOGICAL_SWITCH_PORT $port tag=$tag
}
