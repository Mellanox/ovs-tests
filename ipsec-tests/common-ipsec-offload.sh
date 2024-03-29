IPERF_FILE="/tmp/iperf.log"
TCPDUMP_FILE="/tmp/tcpdump.log"

#run_traffic ipv4/ipv6 [udp|tcp|icmp]
function run_traffic() {
    local IP_PROTO="$1"
    local NET_PROTO="$2"
    local trusted_vfs=${3:-"no_trusted_vfs"}
    local IPERF_EXTRA=""
    local nic=""

    if [[ $trusted_vfs == "trusted_vfs" ]]; then
        nic=$VF
    else
        nic=$NIC
    fi

    if [[ "$NET_PROTO" == "tcp" ]]; then
        :
    elif [[ "$NET_PROTO" == "udp" ]]; then
        IPERF_EXTRA="-u"
    elif [[ "$NET_PROTO" == "icmp" ]]; then
        :
    else
        err "Wrong arg for function run_traffic"
    fi

    local t=10

    title "Run $NET_PROTO traffic"
    rm -f $TCPDUMP_FILE $IPERF_FILE
    if [[ "$NET_PROTO" != "icmp" ]]; then
       start_iperf_server
    fi
    # please notice the no filters on the tcpdump since ipsec encrypt the packets and using crypto offload
    # will require turning TSO/GRO off in some cases in order to capture the expected traffic which will not
    # represent the use case.
    timeout $t tcpdump -qnnei $nic -c 5 -w $TCPDUMP_FILE &
    local upid=$!
    if [[ "$NET_PROTO" == "icmp" ]]; then
        if [[ "$IP_PROTO" == "ipv4" ]]; then
            (on_remote ping $LIP -q -c 10 -i 0.1 -w 3) || err "ping failed"
        else
            (on_remote ping $LIP6 -q -c 10 -i 0.1 -w 3) || err "ping failed"
        fi
    else
        if [[ "$IP_PROTO" == "ipv4" ]]; then
            (on_remote timeout $((t+2)) iperf3 -c $LIP $IPERF_EXTRA -b 2G > $IPERF_FILE) || err "iperf3 failed"
        else
            (on_remote timeout $((t+2)) iperf3 -c $LIP6 $IPERF_EXTRA -b 2G > $IPERF_FILE) || err "iperf3 failed"
        fi
    fi
    if [ $TEST_FAILED == 1 ]; then
        kill $upid 2>/dev/null
        wait $upid 2>/dev/null
    fi
    fail_if_err
    title "Verify $NET_PROTO traffic on $nic"
    verify_have_traffic $upid
}

function get_ipsec_counter() {
    local counter_name="$1"
    local dev=${2:-"$NIC"}

    if [[ "$counter_name" != "tx" &&  "$counter_name" != "rx" ]]; then
        fail "Wrong argument for function get_ipsec_counter"
    fi

    local c="ipsec_${counter_name}_pkts"
    if is_ipsec_ofed_full_offload; then
        c="ipsec_full_${counter_name}_pkts"
    fi

    ethtool -S $dev | grep -w "$c" | awk '{print $2}'
}

function get_ipsec_counter_on_remote() {
    local counter_name="$1"
    local dev=${2:-"$NIC"}

    on_remote_exec "get_ipsec_counter $counter_name $dev"
}

function check_offloaded_rules() {
    local mode=${1:-"both"}
    local tx_check_val=0
    local rx_check_val=0

    if [[ "$mode" == "tx" ]]; then
        tx_check_val=2
    elif [[ "$mode" == "rx" ]];then
        rx_check_val=2
    elif [[ "$mode" == "both" ]]; then
        tx_check_val=2
        rx_check_val=2
    else
        fail "test issue, wrong usage of check_offloaded_rules"
    fi

    title "Verify $offload rules"

    local chk_policy=0
    if [[ "$offload" == "full_offload" ]] && ! is_ipsec_ofed_full_offload; then
        chk_policy=1
    fi

    local g="offload"
    if [[ "$chk_policy" == 1 ]]; then
        g="offload.*mode packet"
    fi

    local tx_off=`on_remote ip x s s | grep -c -w "$g"`
    local rx_off=`ip x s s | grep -c -w "$g"`

    if [[ "$chk_policy" == 1 ]]; then
        local policy_tx_off=`on_remote ip x policy s | grep -c -w "$g"`
        local policy_rx_off=`ip x policy s | grep -c -w "$g"`
    else
        local policy_tx_off=$tx_check_val
        local policy_rx_off=$rx_check_val
    fi

    if [[ "$tx_off" != $tx_check_val || "$rx_off" != $rx_check_val || "$policy_tx_off" != $tx_check_val || "$policy_rx_off" != $rx_check_val ]]; then
        debug "Dumping IPsec rules"
        echo "Local Rules:"
        ip xfrm state show
        ip xfrm policy show
        echo "Remote Rules:"
        on_remote "ip xfrm state show
                   ip xfrm policy show"
        fail "ipsec rules are not offloaded"
    fi
}

function check_full_offload_counters() {
    # counters only supported in full offload/packet offload both upstream and mlnx ofed.
    if [[ ("$offload" != "full_offload" && "$offload" != "packet") ]]; then
        return
    fi

    local pre_tx=$1
    local pre_rx=$2
    local post_tx=$3
    local post_rx=$4
    local msg=$5

    title "Verify offload counters $msg"
    if [[ ("$post_tx" -le "$pre_tx" || "$post_rx" -le "$pre_rx") ]]; then
        fail "IPsec offload counters didn't increase $msg"
    fi
}

#tx offloaded rx not
function test_tx_off_rx() {
    local IPSEC_MODE="$1"
    local KEY_LEN="$2"
    local IP_PROTO="$3"
    local NET_PROTO=${4}
    local TRUSTED_VFS=${5:-"no_trusted_vfs"}
    local offload=${6:-"offload"}

    title "test ipsec in $IPSEC_MODE mode with $KEY_LEN key length using $IP_PROTO with offloaded TX"

    ipsec_config_local $IPSEC_MODE $KEY_LEN $IP_PROTO no-offload $TRUSTED_VFS #in this test local is used as RX
    ipsec_config_remote $IPSEC_MODE $KEY_LEN $IP_PROTO $offload $TRUSTED_VFS

    sleep 2

    if [[ "$offload" == "full_offload" ]]; then
        local pre_tx=`get_ipsec_counter_on_remote tx`
        local pre_rx=`get_ipsec_counter_on_remote rx`
    fi

    run_traffic $IP_PROTO $NET_PROTO $TRUSTED_VFS

    if [[ "$offload" == "full_offload" ]]; then
        local post_tx=`get_ipsec_counter_on_remote tx`
        local post_rx=`get_ipsec_counter_on_remote rx`
    fi

    check_offloaded_rules tx
    check_full_offload_counters $pre_tx $pre_rx $post_tx $post_rx
}

#rx offloaded tx not
function test_tx_rx_off() {
    local IPSEC_MODE="$1"
    local KEY_LEN="$2"
    local IP_PROTO="$3"
    local NET_PROTO=${4}
    local TRUSTED_VFS=${5:-"no_trusted_vfs"}
    local offload=${6:-"offload"}

    title "test ipsec in $IPSEC_MODE mode with $KEY_LEN key length using $IP_PROTO with offloaded RX"

    ipsec_config_local $IPSEC_MODE $KEY_LEN $IP_PROTO $offload $TRUSTED_VFS #in this test local is used as RX
    ipsec_config_remote $IPSEC_MODE $KEY_LEN $IP_PROTO no-offload $TRUSTED_VFS

    sleep 2

    if [[ "$offload" == "full_offload" ]]; then
        local pre_tx=`get_ipsec_counter tx`
        local pre_rx=`get_ipsec_counter rx`
    fi

    run_traffic $IP_PROTO $NET_PROTO $TRUSTED_VFS

    if [[ "$offload" == "full_offload" ]]; then
        local post_tx=`get_ipsec_counter tx`
        local post_rx=`get_ipsec_counter rx`
    fi

    check_offloaded_rules rx
    check_full_offload_counters $pre_tx $pre_rx $post_tx $post_rx
}

#tx & rx are offloaded
function test_tx_off_rx_off() {
    local IPSEC_MODE="$1"
    local KEY_LEN="$2"
    local IP_PROTO="$3"
    local NET_PROTO=${4}
    local TRUSTED_VFS=${5:-"no_trusted_vfs"}
    local offload=${6:-"offload"}

    title "test ipsec in $IPSEC_MODE mode with $KEY_LEN key length using $IP_PROTO with offloaded TX & RX"

    ipsec_config_local $IPSEC_MODE $KEY_LEN $IP_PROTO $offload $TRUSTED_VFS #in this test local is used as RX
    ipsec_config_remote $IPSEC_MODE $KEY_LEN $IP_PROTO $offload $TRUSTED_VFS

    sleep 2

    if [[ "$offload" == "full_offload" ]]; then
        local remote_pre_tx=`get_ipsec_counter_on_remote tx`
        local remote_pre_rx=`get_ipsec_counter_on_remote rx`
        local local_pre_tx=`get_ipsec_counter tx`
        local local_pre_rx=`get_ipsec_counter rx`
    fi

    run_traffic $IP_PROTO $NET_PROTO $TRUSTED_VFS

    if [[ "$offload" == "full_offload" ]]; then
        local remote_post_tx=`get_ipsec_counter_on_remote tx`
        local remote_post_rx=`get_ipsec_counter_on_remote rx`
        local local_post_tx=`get_ipsec_counter tx`
        local local_post_rx=`get_ipsec_counter rx`
    fi

    check_offloaded_rules both
    check_full_offload_counters $remote_pre_tx $remote_pre_rx $remote_post_tx $remote_post_rx "on TX side"
    check_full_offload_counters $local_pre_tx $local_pre_rx $local_post_tx $local_post_rx "on RX side"
}

function cleanup_test() {
    local mtu=${1:-1500}
    local trusted_vfs=${2:-"no_trusted_vfs"}
    local nic="$NIC"
    local remote_nic="$REMOTE_NIC"

    if [[ "$trusted_vfs" == "trusted_vfs" ]]; then
        nic="$VF"
        remote_nic="$VF"
    fi

    kill_iperf
    ipsec_cleanup_on_both_sides
    change_mtu_on_both_sides $mtu $nic $remote_nic
    rm -f $IPERF_FILE $TCPDUMP_FILE
}

function enable_eswitch_encap_mode() {
    local m=`get_eswitch_encap`
    if [ "$m" != "basic" ]; then
        title "Enable eswitch encap mode"
        enable_legacy
        set_eswitch_encap basic
    fi
    devlink dev eswitch show pci/$PCI
}

function disable_eswitch_encap_mode() {
    local m=`get_eswitch_encap`
    if [ "$m" != "none" ]; then
        title "Disable eswitch encap mode"
        enable_legacy
        set_eswitch_encap none
    fi
    devlink dev eswitch show pci/$PCI
}

function reset_eswitch_encap() {
    if [ "$eswitch_encap_enable" == 1 ]; then
        enable_eswitch_encap_mode
        on_remote_exec enable_eswitch_encap_mode
    else
        disable_eswitch_encap_mode
        on_remote_exec disable_eswitch_encap_mode
    fi
}

function cleanup_crypto() {
    cleanup_test
    ipsec_clear_mode_on_both_sides
    reset_eswitch_encap
    enable_switchdev
    on_remote_exec enable_switchdev
}

function config_full() {
    cleanup_test
}

function cleanup_full() {
    cleanup_test
}

IPSEC_KEY_LEN_128=128
IPSEC_KEY_LEN_256=256

# Usage <mtu> <ip_proto> <ipsec_mode> <net_proto> [trusted_vfs]
# mtu = [0-9]*
# ip_proto = ipv4/ipv6
# ipsec_mode = transport/tunnel
# net_proto = tcp/udp/icmp
# adding trusted_vfs option will run the test over trusted VFs instead of PFs
# offload_type = offload/full-offload.
function run_test_ipsec_offload() {
    local mtu=$1
    local ip_proto=$2
    local ipsec_mode=${3:-"transport"}
    local net_proto=${4:-"tcp"}
    local trusted_vfs=${5:-"no_trusted_vfs"}
    local offload_type=${6:-"offload"}
    local len=${7:-$IPSEC_KEY_LEN_128}

    title "test $ipsec_mode $ip_proto over $net_proto with key length $len MTU $mtu with $trusted_vfs"
    cleanup_test $mtu $trusted_vfs

    test_tx_off_rx $ipsec_mode $len $ip_proto $net_proto $trusted_vfs $offload_type
    cleanup_test $mtu $trusted_vfs

    test_tx_rx_off $ipsec_mode $len $ip_proto $net_proto $trusted_vfs $offload_type
    cleanup_test $mtu $trusted_vfs

    test_tx_off_rx_off $ipsec_mode $len $ip_proto $net_proto $trusted_vfs $offload_type
    cleanup_test $mtu $trusted_vfs
}

function performance_config() {
    local ip_proto="$1"
    local ipsec_mode="$2"
    local should_offload="$3"
    ipsec_cleanup_on_both_sides
    ipsec_config_on_both_sides $ipsec_mode 128 $ip_proto $should_offload
}

function run_performance_test() {
    local ipsec_mode=${1:-"transport"}
    local ip_proto=${2:-"ipv4"}

    title "Config ipsec in $ipsec_mode $ip_proto without offload"
    performance_config $ip_proto $ipsec_mode

    title "run traffic"
    local t=15
    start_iperf_server_on_remote

    if [[ "$ip_proto" == "ipv4" ]]; then
        (timeout $((t+10)) iperf3 -c $RIP -t $t -i 5 -f m --logfile /tmp/results.txt ) || err "iperf3 failed"
    else
        (timeout $((t+10)) iperf3 -c $RIP6 -t $t -i 5 -f m --logfile /tmp/results.txt ) || err "iperf3 failed"
    fi
    fail_if_err

    title "Config ipsec in $ipsec_mode $ip_proto with offload"
    performance_config $ip_proto $ipsec_mode offload

    kill_iperf
    start_iperf_server_on_remote

    title "run traffic"
    if [[ "$ip_proto" == "ipv4" ]]; then
        (timeout $((t+10)) iperf3 -c $RIP -t $t -i 5 -f m --logfile /tmp/offload_results.txt ) || err "iperf3 failed"
    else
        (timeout $((t+10)) iperf3 -c $RIP6 -t $t -i 5 -f m --logfile /tmp/offload_results.txt ) || err "iperf3 failed"
    fi
    fail_if_err

    title "Check performance"
    no_off_res=`cat /tmp/results.txt | grep "10.*-15.*" | awk '{print $7}'`
    off_res=`cat /tmp/offload_results.txt | grep "10.*-15.*" | awk '{print $7}'`
    #convert to Mbits
    no_off_res=$(bc <<< "$no_off_res * 1000" | sed -e 's/\..*//')
    off_res=$(bc <<< "$off_res * 1000" | sed -e 's/\..*//')

    if [[ $off_res -le $no_off_res ]]; then
        fail "low offload performance"
    fi
}
