function ovs_add_ct_rules() {
    ovs-ofctl del-flows br-int
    ovs-ofctl add-flow br-int "arp,actions=NORMAL"
    ovs-ofctl add-flow br-int "table=0,ip,ct_state=-trk,actions=ct(zone=5, table=1)"
    ovs-ofctl add-flow br-int "table=1,ip,ct_state=+trk+new,actions=ct(zone=5, commit),NORMAL"
    ovs-ofctl add-flow br-int "table=1,ip,ct_state=+trk+est,ct_zone=5,actions=normal"
    echo "OVS flow rules:"
    ovs-ofctl dump-flows br-int --color
}

function verify_ping() {
    local remote_ip=${1:-$REMOTE_IP}
    local namespace=${2:-ns0}
    echo "Testing ping $remote_ip in namespace $namespace"
    ip netns exec $namespace ping -q -c 10 -w 1 -i 0.01 $remote_ip
    if [ $? -ne 0 ]; then
        err "ping failed"
        return 1
    fi
}

function generate_traffic() {
    local remote=${1:-"local"}
    local my_ip=${2:-$LOCAL_IP}
    local namespace=$3
    local t=5

    echo -e "\nTesting TCP traffic remote = $remote , ip = $my_ip , namespace = $namespace"

    # server
    ip netns exec ns0 timeout $((t+2)) iperf3 -f Mbits -s -D --logfile /tmp/perf_server
    sleep 2
    # client
    local cmd="iperf3 -f Mbits -c $my_ip -t $t -P 5 --logfile /tmp/perf_client"
    if [ -n "$namespace" ]; then
        cmd="ip netns exec $namespace $cmd"
    fi

    if [ "$remote" == "remote" ]; then
        cmd="on_remote $cmd"
    fi

    eval $cmd &
    local pid2=$!

    # verify pid
    sleep 1
    kill -0 $pid2 &>/dev/null
    if [ $? -ne 0 ]; then
       err "iperf3 failed"
       return 1
    fi

    sleep $t
    validate_traffic 1
    kill_iperf
}

function validate_traffic() {
    local min_traffic=$1
    local server_traffic=$(cat /tmp/perf_server | grep "SUM" | grep "MBytes/sec" | awk '{print $6}' | head -1)
    local client_traffic=$(cat /tmp/perf_client | grep "SUM" | grep "MBytes/sec" | awk '{print $6}' | head -1)

    echo "validate traffic server: $server_traffic , client: $client_traffic"
    if [[ -z $server_traffic || $server_traffic < $1 ]]; then
        err "server traffic is $server_traffic, lower than limit $min_traffic"
    fi

    if [[ -z $client_traffic ||  $client_traffic < $1 ]]; then
        err "client traffic is $client_traffic, lower than limit $min_traffic"
    fi
}

function kill_iperf() {
   killall -9 iperf3 &>/dev/null
   sleep 1
}

function remote_ovs_cleanup() {
    title "Cleaning up remote"
    on_remote_dt "ip a flush dev $NIC
                  ip netns del ns0 &>/dev/null
                  start_clean_openvswitch"
}

function cleanup_test() {
    ip a flush dev $NIC
    ip -all netns delete &>/dev/null
    cleanup_e2e_cache
    cleanup_remote_tunnel
    sleep 0.5
}
