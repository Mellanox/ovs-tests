OVN_BRIDGE_INT="br-int"
OVN_CTL="/usr/share/ovn/scripts/ovn-ctl"
OVN_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)

. $OVN_DIR/../common.sh

if [ "$DPDK" == 1 ]; then
    . $OVN_DIR/../ovs-dpdk-tests/common-dpdk.sh
fi

# Tunnels
TUNNEL_GENEVE="geneve"

# Traffic type
ETH_IP="0x0800"
ETH_IP6="0x86dd"

. $OVN_DIR/common-ovn-topology.sh

# OVN IPs
OVN_LOCAL_CENTRAL_IP="127.0.0.1"
OVN_CENTRAL_IP="192.168.100.100"
OVN_CENTRAL_IPV6="192:168:100::100"
OVN_REMOTE_CONTROLLER_IP="192.168.100.101"
OVN_REMOTE_CONTROLLER_IPV6="192:168:100::101"

OVN_EXTERNAL_NETWORK_HOST_IP="172.16.1.10"
OVN_EXTERNAL_NETWORK_HOST_IP_V6="172:16:1::A"

OVN_TUNNEL_MTU=1700

OVN_BOND="bond0"
OVN_PF_BRIDGE="br-pf"
OVN_VLAN_INTERFACE="vlan-int"
OVN_VLAN_TAG=100
PF_VLAN_INT="${NIC}.$OVN_VLAN_TAG"
BOND_VLAN_INT="${OVN_BOND}.$OVN_VLAN_TAG"

# Traffic Filters
# Ignore IPv6 Neighbor-Advertisement, Neighbor Solicitation and Router Solicitation packets
TCPDUMP_IGNORE_IPV6_NEIGH="icmp6 and ip6[40] != 133 and ip6[40] != 135 and ip6[40] != 136"

declare -A TRAFFIC_INFO=(
    ['offloaded_traffic_timeout']=15
    ['offloaded_traffic_verification_delay']=5
    ['offloaded_traffic_timeout_tcp']=40
    ['offloaded_traffic_verification_delay_tcp']=30
    ['offloaded_traffic_time_window']=3
    ['non_offloaded_traffic_timeout']=5
    ['non_offloaded_packets']=40
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
    ['bf_external']=""
)

function require_ovn() {
    [ -e "${OVN_CTL}" ] || fail "Missing $OVN_CTL"
}

function require_bf_ovn() {
    on_bf "test -e $OVN_CTL" || fail "Missing $OVN_CTL on BF"
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

    if [ "$DPDK" == 1 ]; then
        ovs-vsctl set open . external-ids:ovn-bridge-datapath-type=netdev
    fi
}

function ovn_remove_ovs_config() {
    if [ "$DPDK" == 1 ]; then
      ovs-vsctl remove open . external-ids ovn-bridge-datapath-type
    fi

    ovs-vsctl remove open . external-ids ovn-remote
    ovs-vsctl remove open . external-ids ovn-encap-ip
    ovs-vsctl remove open . external-ids ovn-encap-type
}

function ovs_add_port_to_switch() {
    local br=$1
    local port=$2
    local extra_args=$3

    ovs-vsctl add-port $br $port $extra_args
}

function ovn_bind_port() {
    local port=$1
    local ovn_port=$2
    local dpdk_options

    if [ "$DPDK" == 1 ]; then
        local vf_id=$(cat /sys/class/net/$port/phys_port_name | sed 's/pf.vf//')
        local pci=$(get_pf_pci)

        dpdk_options="-- set interface $port type=dpdk options:dpdk-devargs=$pci,representor=[$vf_id],$DPDK_PORT_EXTRA_ARGS"
    fi

    ovs-vsctl --may-exist add-port $OVN_BRIDGE_INT $port -- set Interface $port external_ids:iface-id=$ovn_port $dpdk_options
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
    local t=20

    echo "send traffic start `date`"
    if [[ $traffic_type == "icmp" ]]; then
        ip netns exec $ns ping -w $timeout -i 0.001 $dst_ip >$logfile &
    elif [[ $traffic_type == "icmp6" ]]; then
        ip netns exec $ns ping -6 -w $timeout -i 0.001 $dst_ip >$logfile &
    elif [[ $traffic_type == "tcp" ]]; then
        ip netns exec $ns timeout $((timeout+t)) iperf3 -t $timeout -c $dst_ip --logfile $logfile --bitrate 1G &
    elif [[ $traffic_type == "tcp6" ]]; then
        ip netns exec $ns timeout $((timeout+t)) iperf3 -6 -t $timeout -c $dst_ip --logfile $logfile --bitrate 1G &
    elif [[ $traffic_type == "udp" ]]; then
        local packets=$((timeout * 1000))
        ip netns exec $ns timeout $((timeout+t)) $OVN_DIR/udp-perf.py -c $dst_ip --packets $packets -i 0.001 --pass-rate 0.7 --logfile $logfile &
    elif [[ $traffic_type == "udp6" ]]; then
        local packets=$((timeout * 1000))
        ip netns exec $ns timeout $((timeout+t)) $OVN_DIR/udp-perf.py -6 -c $dst_ip --packets $packets -i 0.001 --pass-rate 0.7 --logfile $logfile &
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
    local bf_traffic=${TRAFFIC_INFO['bf_traffic']}
    local dump="/tmp/tcpdump-$rep-${tcpdump_filter// /_}"

    if [[ -z "$bf_traffic" ]]; then
        rm -f "$dump"
        timeout -k3 $traffic_timeout tcpdump -Unnepi $rep $tcpdump_filter -c $non_offloaded_packets -w "$dump" >/dev/null &
        tdpid=$!
    else
        on_bf "rm -f $dump ; timeout -k3 $traffic_timeout tcpdump -Unnepi $rep $tcpdump_filter -c $non_offloaded_packets -w $dump >/dev/null" &
        tdpid=$!
    fi
}

function __start_tcpdump() {
    local rep=$1
    local tcpdump_filter=$2
    local non_offloaded_packets=$3
    local local_traffic=${TRAFFIC_INFO['local_traffic']}
    local bf_traffic=${TRAFFIC_INFO['bf_traffic']}
    local dump="/tmp/tcpdump-$rep-${tcpdump_filter// /_}"

    if [[ -n "$local_traffic" ]]; then
        __start_tcpdump_local $rep "$tcpdump_filter" $non_offloaded_packets
    elif [[ -z "$bf_traffic" ]]; then
        on_remote "rm -f $dump ; timeout -k3 $traffic_timeout tcpdump -Unnepi $rep $tcpdump_filter -c $non_offloaded_packets -w $dump >/dev/null" &
        tdpid=$!
    else
        on_remote_bf "rm -f $dump ; timeout -k3 $traffic_timeout tcpdump -Unnepi $rep $tcpdump_filter -c $non_offloaded_packets -w $dump >/dev/null" &
        tdpid=$!
    fi
}

function __verify_tcpdump() {
    local pid=$1
    wait $pid
    local rc=$?
    if [ $rc == 124 ]; then
        success
    elif [ $rc == 0 ]; then
        err "Failed offload"
    elif [ $rc == 137 ]; then
        warn "tcpdump terminated rc $rc"
    else
        err "tcpdump rc $rc"
    fi
}

function __verify_tcpdump_offload_local() {
    local tdpid=$1
    local bf_traffic=${TRAFFIC_INFO['bf_traffic']}

    # tdpid is always local.
    __verify_tcpdump $tdpid
}

function __verify_tcpdump_offload() {
    local tdpid=$1
    local local_traffic=${TRAFFIC_INFO['local_traffic']}
    local bf_traffic=${TRAFFIC_INFO['bf_traffic']}

    # doesn't matter if local, bf, remote. because tdpid is always local.
    __verify_tcpdump_offload_local $tdpid
}

function __verify_testpmd_offload_local() {
    local ns=$1
    local vf=$2
    local prev_tx_vf_pkts=$3
    local prev_rx_vf_pkts=$4
    local bf_traffic=${TRAFFIC_INFO[bf_traffic]}

    local valid_percentage_passed_in_sw=10

    local total_packets_passed_in_sw
    local all_packets_passed

    echo "query the stats of packets passed in SW"
    if [[ -z "$bf_traffic" ]]; then
        total_packets_passed_in_sw=$(get_total_packets_passed_in_sw)
    else
        total_packets_passed_in_sw=$(on_bf_exec "get_total_packets_passed_in_sw")
    fi

    if [ -z "$total_packets_passed_in_sw" ]; then
      err "ERROR: Cannot get total_packets_passed_in_sw"
      return 1
    fi

    all_tx_packets_passed=$(get_tx_pkts_ns $ns $vf)
    all_rx_packets_passed=$(get_rx_pkts_ns $ns $vf)

    if [ -z "$all_tx_packets_passed" ]; then
        err "ERROR: Cannot get all_tx_packets_passed"
        return 1
    fi

    if [ -z "$all_rx_packets_passed" ]; then
        err "ERROR: Cannot get all_rx_packets_passed"
        return 1
    fi

    all_tx_packets_passed=$((all_tx_packets_passed-prev_tx_vf_pkts))
    all_rx_packets_passed=$((all_rx_packets_passed-prev_rx_vf_pkts))

    title "Checking $total_packets_passed_in_sw is no more than $valid_percentage_passed_in_sw% of $all_tx_packets_passed (sent packets)"
    if [ $(($valid_percentage_passed_in_sw*$total_packets_passed_in_sw)) -gt $all_tx_packets_passed ]; then
        err "$total_packets_passed_in_sw packets passed in SW, it is more than $valid_percentage_passed_in_sw% of $all_tx_packets_passed"
        return 1
    fi

    title "Checking $total_packets_passed_in_sw is no more than $valid_percentage_passed_in_sw% of $all_rx_packets_passed (received packets)"
    if [ $(($valid_percentage_passed_in_sw*$total_packets_passed_in_sw)) -gt $all_rx_packets_passed ]; then
        err "$total_packets_passed_in_sw packets passed in SW, it is more than $valid_percentage_passed_in_sw% of $all_rx_packets_passed"
        return 1
    fi

    return 0
}


function check_traffic_offload() {
    local server_ip=$1
    local traffic_type=$2

    local client_ns=${TRAFFIC_INFO['client_ns']}
    local client_vf=${TRAFFIC_INFO['client_vf']}
    local client_rep=${TRAFFIC_INFO['client_rep']}
    local client_rule_fields=${TRAFFIC_INFO['client_rule_fields']}
    local client_verify_offload=${TRAFFIC_INFO['client_verify_offload']}

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local server_vf=${TRAFFIC_INFO['server_vf']}
    local server_rep=${TRAFFIC_INFO['server_rep']}
    local server_rule_fields=${TRAFFIC_INFO['server_rule_fields']}
    local server_verify_offload=${TRAFFIC_INFO['server_verify_offload']}

    local non_offloaded_packets=${TRAFFIC_INFO['non_offloaded_packets']}
    local skip_offload=${TRAFFIC_INFO['skip_offload']}
    local local_traffic=${TRAFFIC_INFO['local_traffic']}
    local bf_traffic=${TRAFFIC_INFO['bf_traffic']}
    local tcpdump_filter=$(__tcpdump_filter $traffic_type)

    local client_vf_tx_pkts
    local client_vf_rx_pkts
    local server_vf_tx_pkts
    local server_vf_rx_pkts

    if [[ -z $client_verify_offload ]] && [[ -z $server_verify_offload ]]; then
        skip_offload=1
    fi

    # Send background traffic before capturing traffic
    title "Sending ${traffic_type^^} traffic"
    local logfile=$(mktemp)
    local traffic_timeout=${TRAFFIC_INFO['offloaded_traffic_timeout']}
    if [[ "$traffic_type" == "tcp" || "$traffic_type" == "tcp6" ]]; then
         traffic_timeout=${TRAFFIC_INFO['offloaded_traffic_timeout_tcp']}
    fi
    if [[ -n "$skip_offload" ]]; then
        traffic_timeout=${TRAFFIC_INFO['non_offloaded_traffic_timeout']}
    fi

    local vf_tx_pkts=`get_tx_pkts_ns $client_ns $client_vf`
    local vf_rx_pkts=`get_rx_pkts_ns $client_ns $client_vf`

    echo "logfile: $logfile"
    send_background_traffic $traffic_type $client_ns $server_ip $traffic_timeout $logfile
    local traffic_pid=$!

    if [[ -n "$skip_offload" ]]; then
        wait $traffic_pid && success || err
        ovs_flush_rules
        return
    fi

    tmp=${TRAFFIC_INFO['offloaded_traffic_verification_delay']}
    if [[ "$traffic_type" == "tcp" || "$traffic_type" == "tcp6" ]]; then
        tmp=${TRAFFIC_INFO['offloaded_traffic_verification_delay_tcp']}
    fi
    echo "Sleep for $tmp seconds initial traffic"
    sleep $tmp
    head -n5 $logfile

    __check_vf_counters
    local counters_ok=$?

    if [[ $counters_ok == 1 ]]; then
        ### start_tcpdump
        if [[ -n $client_verify_offload ]]; then
            if [ "$DPDK" == 1 ]; then
                __start_testpmd_offload_client
            else
                echo "Start sender tcpdump"
                __start_tcpdump_local $client_rep "$tcpdump_filter" $non_offloaded_packets
                tdpid=$tdpid
            fi
        fi

        if [[ -n $server_verify_offload ]]; then
            if [ "$DPDK" == 1 ]; then
                __start_testpmd_offload_server
            else
                echo "Start receiver tcpdump"
                tmp=$tdpid
                __start_tcpdump $server_rep "$tcpdump_filter" $non_offloaded_packets
                tdpid_receiver=$tdpid
                tdpid=$tmp
            fi
        fi
        ####
    else
        warn "Skipping tcpdump offload check"
    fi

    if [[ -n $client_rule_fields ]]; then
        title "Check ${traffic_type^^} OVS offload rules on the sender"
        __verify_client_rules "$client_rule_fields"
    fi

    if [[ -z "$local_traffic" ]] && [[ -n $server_rule_fields ]]; then
        title "Check ${traffic_type^^} OVS offload rules on the receiver"
        __verify_server_rules "$server_rule_fields"
    fi

    if [ "$DPDK" == 1 ]; then
      echo "sleep until the traffic is finished"
      wait $traffic_pid
    fi

    if [[ $counters_ok == 1 ]]; then
        ### veirfy_tcpdump
        # If tcpdump finished then it capture more than expected to be offloaded
        sleep "${TRAFFIC_INFO['offloaded_traffic_time_window']}"

        if [[ -n $client_verify_offload ]]; then
            title "Check ${traffic_type^^} traffic is offloaded on the sender"
            if [ "$DPDK" == 1 ]; then
               __verify_testpmd_offload_local "$CLIENT_NS" "$CLIENT_VF" "$client_vf_tx_pkts" "$client_vf_rx_pkts"
            else
               __verify_tcpdump_offload_local $tdpid
            fi
        fi

        if [[ -n $server_verify_offload ]]; then

            title "Check ${traffic_type^^} traffic is offloaded on the receiver"
            if [ "$DPDK" == 1 ]; then
              __verify_offload_testpmd $SERVER_NS $SERVER_VF $server_vf_tx_pkts $server_vf_rx_pkts
            else
              __verify_offload_tcpdump $tdpid_receiver
            fi

        fi
        #####
    fi

    title "Wait ${traffic_type^^} traffic"
    verify_traffic_pid $traffic_pid

    if [[ -z "$bf_traffic" ]]; then
        __ovs_flush_rules_both
    else
        __bf_ovs_flush_rules_both
    fi
}

function __check_vf_counters() {
    title "Check vf counters"

    local vf_tx_pkts2=`get_tx_pkts_ns $client_ns $client_vf`
    local vf_rx_pkts2=`get_rx_pkts_ns $client_ns $client_vf`
    let tx_diff=vf_tx_pkts2-vf_tx_pkts
    let rx_diff=vf_rx_pkts2-vf_rx_pkts
    local expected=10
    local counters_ok=1

    if [[ $tx_diff -ge $expected ]]; then
        success2 tx_counter
    else
        counters_ok=0
        err "TX counter diff $tx_diff < $expected"
    fi

    if [[ $rx_diff -ge $expected ]]; then
        success2 rx_counter
    else
        counters_ok=0
        err "RX counter diff $rx_diff < $expected"
    fi

    return $counters_ok
}

function __ovs_flush_rules_both() {
    ovs_flush_rules
    if [[ -z "$local_traffic" ]]; then
        on_remote_exec "ovs_flush_rules"
    fi
}

function __bf_ovs_flush_rules_both() {
    on_bf_exec "ovs_flush_rules"
    if [[ -z "$local_traffic" ]]; then
        on_remote_bf_exec "ovs_flush_rules"
    fi
}

function verify_traffic_pid() {
    local pid=$1
    wait $pid
    local rc=$?
    echo "check traffic time `date`"
    if [[ $rc -eq 124 ]]; then
        err "Failed for process timeout"
    elif [[ $rc -eq 0 ]]; then
        success
    else
        tail -n5 $logfile
        err "Failed with rc $rc"
    fi
}

function __start_testpmd_offload_client() {
  client_vf_tx_pkts=$(get_tx_pkts_ns $client_ns $client_vf)
  client_vf_rx_pkts=$(get_rx_pkts_ns $client_ns $client_vf)

  echo "clearing pmd stats in client"
  if [[ -z "$bf_traffic" ]]; then
      clear_pmd_stats
  else
      on_bf_exec "clear_pmd_stats"
  fi
}

function __start_testpmd_offload_server() {
  echo "clearing pmd stats in server"
  if [[ -z "$local_traffic" ]]; then
    server_vf_tx_pkts=$(on_remote_exec "get_tx_pkts_ns $server_ns $server_vf")
    server_vf_rx_pkts=$(on_remote_exec "get_rx_pkts_ns $server_ns $server_vf")

    if [[ -z "$bf_traffic" ]]; then
      on_remote_exec "clear_pmd_stats"
    else
      on_remote_bf_exec "clear_pmd_stats"
    fi

  else
    server_vf_tx_pkts=$(get_tx_pkts_ns $server_ns $server_vf)
    server_vf_rx_pkts=$(get_rx_pkts_ns $server_ns $server_vf)
  fi
}

function __verify_offload_testpmd() {
  local ns=$1
  local vf=$2
  local prev_tx_vf_pkts=$3
  local prev_rx_vf_pkts=$4

  if [[ -z "$local_traffic" ]]; then
      on_remote_exec "__verify_testpmd_offload_local $ns $vf $prev_tx_vf_pkts $prev_rx_vf_pkts" || err "verify remote offload failed"
  else
     __verify_testpmd_offload_local "$ns" "$vf" "$prev_tx_vf_pkts" "$prev_rx_vf_pkts"
  fi
}

function __verify_offload_tcpdump() {
  local tcpdump_pid=$1

  if [[ -z "$local_traffic" ]]; then
      __verify_tcpdump_offload $tcpdump_pid
  else
      __verify_tcpdump_offload_local $tcpdump_pid
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

function on_remote_wrap() {
    local cmd=$1

    if [[ -n "${TRAFFIC_INFO['local_traffic']}" ]]; then
        eval $cmd
    elif [[ -n "${TRAFFIC_INFO['bf_external']}" ]]; then
        on_remote_bf "$cmd"
    else
        on_remote "$cmd"
    fi
}

function check_local_tcp_traffic_offload() {
    check_remote_tcp_traffic_offload $@
}

function check_local_tcp6_traffic_offload() {
    check_remote_tcp6_traffic_offload $@
}

function check_remote_tcp_traffic_offload() {
    local server_ip=$1

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local cmd=$(ns_wrap "iperf3 -s -D" $server_ns)
    on_remote_wrap "$cmd"
    sleep 0.5

    check_traffic_offload $server_ip tcp
    on_remote_wrap "killall -q iperf3"
}

function check_remote_tcp6_traffic_offload() {
    local server_ip=$1

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local cmd=$(ns_wrap "iperf3 -6 -s -D" $server_ns)
    on_remote_wrap "$cmd"
    sleep 0.5

    check_traffic_offload $server_ip tcp6
    on_remote_wrap "killall -q iperf3"
}

function check_local_udp_traffic_offload() {
    check_remote_udp_traffic_offload $@
}

function check_local_udp6_traffic_offload() {
    check_remote_udp6_traffic_offload $@
}

function check_remote_udp_traffic_offload() {
    local server_ip=$1

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local cmd=$(ns_wrap "timeout 15 $OVN_DIR/udp-perf.py -s -D" $server_ns)
    on_remote_wrap "$cmd"
    sleep 0.5

    check_traffic_offload $server_ip udp
    on_remote_wrap "killall -q udp-perf.py"
}

function check_remote_udp6_traffic_offload() {
    local server_ip=$1

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local cmd=$(ns_wrap "timeout 15 $OVN_DIR/udp-perf.py -6 -s -D" $server_ns)
    on_remote_wrap "$cmd"
    sleep 0.5

    check_traffic_offload $server_ip udp6
    on_remote_wrap "killall -q udp-perf.py"
}

function check_fragmented_traffic() {
    local rep=$1
    local ns=$2
    local dst_ip=$3
    local size=$4
    local is_ipv6=$5

    local client_ns=${TRAFFIC_INFO['client_ns']}
    local client_vf=${TRAFFIC_INFO['client_vf']}

    local server_ns=${TRAFFIC_INFO['server_ns']}
    local server_vf=${TRAFFIC_INFO['server_vf']}

    local local_traffic=${TRAFFIC_INFO['local_traffic']}
    local traffic_filter=$ETH_IP
    local rules_filter=ip
    local tcpdump_filter=icmp

    local client_vf_tx_pkts
    local client_vf_rx_pkts
    local server_vf_tx_pkts
    local server_vf_rx_pkts

    if [[ -n "$is_ipv6" ]]; then
        traffic_filter=$ETH_IP6
        rules_filter=ipv6
        tcpdump_filter=$TCPDUMP_IGNORE_IPV6_NEIGH
    fi

    title "Sending traffic"
    local logfile=$(mktemp)
    local traffic_timeout=${TRAFFIC_INFO['offloaded_traffic_timeout']}
    if [[ -z "$is_ipv6" ]]; then
        ip netns exec $ns ping -s $size -w $traffic_timeout $dst_ip -i 0 >$logfile &
    else
        ip netns exec $ns ping -6 -s $size -w $traffic_timeout $dst_ip -i 0 >$logfile &
    fi
    local traffic_pid=$!

    echo "Sleep for ${TRAFFIC_INFO['offloaded_traffic_verification_delay']} seconds initial traffic"
    sleep ${TRAFFIC_INFO['offloaded_traffic_verification_delay']}
    head -n5 $logfile

    if [[ "$DPDK" == 1 ]]; then
      __start_testpmd_offload_client
      __start_testpmd_offload_server

    else
      # Listen to traffic on representor
      timeout 10 tcpdump -Unnepi $rep $tcpdump_filter -c 8 &
      local tdpid=$!
    fi

    title "Check OVS Rules"
    ovs_dump_flows --names filter="$rules_filter"
    check_fragmented_rules $traffic_filter

    if [ "$DPDK" == 1 ]; then
      echo "sleep until the traffic is finished"
      wait $traffic_pid
    fi

    title "Check captured packets count"
    if [[ "$DPDK" == 1 ]]; then
        title "Check ${traffic_type^^} traffic is offloaded on the sender"
        __verify_testpmd_offload_local "$CLIENT_NS" "$CLIENT_VF" "$client_vf_tx_pkts" "$client_vf_rx_pkts"

        if [[ -z "$local_traffic" ]]; then
            __verify_offload_testpmd $SERVER_NS $SERVER_VF $server_vf_tx_pkts $server_vf_rx_pkts
        fi

    else
        # Offloading fragmented traffic is not supported in upstream
        # Wait tcpdump to finish and verify traffic is not offloaded
        verify_have_traffic $tdpid
    fi

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
    local dpdk_bridge_options=""

    if [ "$DPDK" == 1 ]; then
        dpdk_bridge_options="-- set bridge $br datapath_type=netdev"
    fi

    ovs-vsctl --may-exist add-br $br $dpdk_bridge_options
    ovs-vsctl add-port $br $interface tag=$vlan -- set Interface $interface type=internal
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
    local dpdk_bridge_options=""
    local dpdk_port_options=""
    local pci

    if [ "$DPDK" == 1 ]; then
        pci=$(get_pf_pci)
        dpdk_bridge_options="-- set bridge $br datapath_type=netdev"
        dpdk_port_options="-- set interface $network_iface type=dpdk options:dpdk-devargs=$pci,$DPDK_PORT_EXTRA_ARGS"
    fi
    ovs-vsctl --may-exist add-br $br $dpdk_bridge_options
    ovs-vsctl add-port $br $network_iface $dpdk_port_options
    ovs-vsctl set Open_vSwitch . external_ids:ovn-bridge-mappings=$network:$br
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

function get_dpdk_pf_port_extra_args() {
    local args=""

    if [ "$DPDK" == 1 ]; then
        local pci=$(get_pf_pci)
        local nic=$NIC

        if is_bf; then
            nic=$BF_NIC
        fi

        args="-- set Interface $nic type=dpdk options:dpdk-devargs=$pci,$DPDK_PORT_EXTRA_ARGS"
    fi
    echo "$args"
}

function WA_dpdk_initial_ping_and_flush() {
    if [[ "$DPDK" == 1 ]]; then
        # WA RM #3287703 require initial traffic + flush to start working.
        echo "Init traffic"
        ip netns exec $CLIENT_NS ping -w 1 $SERVER_IPV4 &> /dev/null

        if is_bf_host; then
            on_bf_exec ovs_flush_rules
        else
            ovs_flush_rules
        fi

    fi
}

function __reset_nic() {
    local nic=${1:-$NIC}

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

function __ovn_set_ipv6_ips() {
    title "Config OVN controller IPv6"
    ovn_central_ip=$OVN_CENTRAL_IPV6
    ovn_controller_ip=$OVN_CENTRAL_IPV6
    ovn_remote_controller_ip=$OVN_REMOTE_CONTROLLER_IPV6
}

function ovn_set_ips() {
    if [ "$OVN_SET_CONTROLLER_IPV6" == 1 ]; then
        __ovn_set_ipv6_ips
        return
    fi
    title "Config OVN controller IPv4"
    ovn_central_ip=$OVN_CENTRAL_IP
    ovn_controller_ip=$OVN_CENTRAL_IP
    ovn_remote_controller_ip=$OVN_REMOTE_CONTROLLER_IP
}
