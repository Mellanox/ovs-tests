MACSEC_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
. $MACSEC_DIR/../common.sh

require_cmd xxd

MACSEC_CONFIG="$TESTDIR/macsec-config.sh"

LIP="1.1.1.1"
RIP="1.1.1.2"
MACSEC_LIP="2.2.2.1"
MACSEC_RIP="2.2.2.2"
MACSEC_LIP6="2001:192:168:200::64"
MACSEC_RIP6="2001:192:168:200::65"
LIP6="2001:192:168:211::64"
RIP6="2001:192:168:211::65"
CLIENT_PN=$(($RANDOM % 10000))
SERVER_PN=$(($RANDOM % 10000))


# KEYMAT 20 octets = KEY 16ocets, SALT 4octets
# 128 refers to the KEY without the SALT.
KEY_IN_128=`dd if=/dev/urandom count=16 bs=1 2>/dev/null | xxd -p -c 40`
KEY_OUT_128=`dd if=/dev/urandom count=16 bs=1 2>/dev/null | xxd -p -c 40`

# KEYMAT 36 octets = KEY 32ocets, SALT 4octets
# 256 refers to the KEY without the SALT.
KEY_IN_256=`dd if=/dev/urandom count=32 bs=1 2>/dev/null | xxd -p -c 72`
KEY_OUT_256=`dd if=/dev/urandom count=32 bs=1 2>/dev/null | xxd -p -c 72`

IPERF_FILE="/tmp/iperf.log"
TCPDUMP_FILE="/tmp/tcpdump.log"

function macsec_parse_test() {
    MTU=""
    IP_PROTO=""
    MACSEC_IP_PROTO=""
    NET_PROTO=""
    OFFLOAD_SIDE=""
    XPN="off"
    MULTI_SA="off"
    while [[ $# -gt 0 ]]; do
        local key="$1"
        case $key in
            --mtu)
            MTU="$2"
            shift 2
            ;;
            --ip-proto)
            IP_PROTO="$2"
            shift 2
            ;;
            --macsec-ip-proto)
            MACSEC_IP_PROTO="$2"
            shift 2
            ;;
            --net-proto)
            NET_PROTO="$2"
            shift 2
            ;;
            --offload-side)
            OFFLOAD_SIDE="$2"
            shift 2
            ;;
            --multi-sa)
            MULTI_SA="$2"
            shift 2
            ;;
            --xpn)
            XPN="$2"
            shift 2
            ;;
            --client_pn)
            CLIENT_PN="$2"
            shift 2
            ;;
            --server_pn)
            SERVER_PN="$2"
            shift 2
            ;;
            *)    # Unknown option
            fail "Unknown arg for macsec test parser"
            ;;
        esac
    done
}

function macsec_set_key_len() {
    KEY_LEN=$1
}

function macsec_set_config_extras() {
    if [ "$OFFLOAD_SIDE" == "local" ]; then
        LOCAL_EXTRA="--offload $@"
        REMOTE_EXTRA=""
    elif [ "$OFFLOAD_SIDE" == "remote" ]; then
        LOCAL_EXTRA=""
        REMOTE_EXTRA="--offload $@"
    elif [ "$OFFLOAD_SIDE" == "both" ]; then
        LOCAL_EXTRA="--offload $@"
        REMOTE_EXTRA="--offload $@"
    elif [ "$OFFLOAD_SIDE" == "none" ]; then
        LOCAL_EXTRA="$@"
        REMOTE_EXTRA="$@"
    else
        fail "OFFLOAD_SIDE=$OFFLOAD_SIDE is not a valid value"
    fi
}

function macsec_cleanup_local() {
    local dev=${1:-"$NIC"}
    local macsec_dev=${2:-"macsec0"}
    ip address flush $dev
    ip link show | grep $macsec_dev > /dev/null && ip link del $macsec_dev
}

function macsec_cleanup_remote() {
    local dev=${1:-"$NIC"}
    local macsec_dev=${2:-"macsec0"}
    on_remote_exec "macsec_cleanup_local $dev $macsec_dev"
}

function macsec_reset_defaults() {
    EFFECTIVE_LIP="$LIP/24"
    EFFECTIVE_RIP="$RIP/24"
    MACSEC_EFFECTIVE_LIP="$MACSEC_LIP/24"
    MACSEC_EFFECTIVE_RIP="$MACSEC_RIP/24"
    EFFECTIVE_CIPHER="gcm-aes-128"
    EFFECTIVE_KEY_IN="$KEY_IN_128"
    EFFECTIVE_KEY_OUT="$KEY_OUT_128"
    KEY_LEN=128
}

function macsec_cleanup() {
    local mtu=${1:-"1500"}
    local dev=${2:-"$NIC"}
    local macsec_dev=${3:-"macsec0"}
    macsec_cleanup_local $dev $macsec_dev
    macsec_cleanup_remote $dev $macsec_dev
    macsec_reset_defaults
}

function start_iperf_server_on_remote() {
    on_remote "iperf3 -s -D"
    sleep 2
}

function start_iperf_server() {
    iperf3 -s -D
    sleep 2
}

function kill_iperf() {
    on_remote killall -9 iperf3 &>/dev/null
    killall -9 iperf3 &>/dev/null
}

function change_mtu_on_both_sides() {
    local mtu_val=${1:-"1500"}
    local dev=${2:-"$NIC"}
    local macsec_dev=${3:-"macsec0"}
    ip link set $dev mtu $mtu_val
    ip link set $macsec_dev mtu $((mtu_val-32))
    on_remote "ip link set $dev mtu $mtu_val
               ip link set $macsec_dev mtu $((mtu_val-32))"
}

function get_macsec_counter() {
  local counter=$1
  local dev=${2:-$NIC}

  counter="macsec_${counter}"
  res=`ethtool -S $dev | grep -w "$counter" | awk '{print $2}'`
  [ -z "$res" ] && fail "Cannot find counter $counter"
  echo $res
}

function get_macsec_counter_on_remote() {
    local counter="$1"
    local dev=${2:-"$NIC"}

    on_remote_exec "get_macsec_counter $counter $dev"
}

function read_pre_test_counters() {

    if [ "$OFFLOAD_SIDE" == "none" ]; then
        return
    fi

    if [ "$OFFLOAD_SIDE" == "remote" ]; then
        REMOTE_PRE_TEST_PKTS_TX=`on_remote_exec "get_macsec_counter tx_pkts"`
        REMOTE_PRE_TEST_PKTS_RX=`on_remote_exec "get_macsec_counter rx_pkts"`
        REMOTE_PRE_TEST_PKTS_TX_DROP=`on_remote_exec "get_macsec_counter tx_pkts_drop"`
        REMOTE_PRE_TEST_PKTS_RX_DROP=`on_remote_exec "get_macsec_counter rx_pkts_drop"`
    elif [ "$OFFLOAD_SIDE" == "local" ]; then
        LOCAL_PRE_TEST_PKTS_TX=`get_macsec_counter tx_pkts`
        LOCAL_PRE_TEST_PKTS_RX=`get_macsec_counter rx_pkts`
        LOCAL_PRE_TEST_PKTS_TX_DROP=`get_macsec_counter tx_pkts_drop`
        LOCAL_PRE_TEST_PKTS_RX_DROP=`get_macsec_counter rx_pkts_drop`
    else
        LOCAL_PRE_TEST_PKTS_TX=`get_macsec_counter tx_pkts`
        LOCAL_PRE_TEST_PKTS_RX=`get_macsec_counter rx_pkts`
        REMOTE_PRE_TEST_PKTS_TX=`on_remote_exec "get_macsec_counter tx_pkts"`
        REMOTE_PRE_TEST_PKTS_RX=`on_remote_exec "get_macsec_counter rx_pkts"`
        LOCAL_PRE_TEST_PKTS_TX_DROP=`get_macsec_counter tx_pkts_drop`
        LOCAL_PRE_TEST_PKTS_RX_DROP=`get_macsec_counter rx_pkts_drop`
        REMOTE_PRE_TEST_PKTS_TX_DROP=`on_remote_exec "get_macsec_counter tx_pkts_drop"`
        REMOTE_PRE_TEST_PKTS_RX_DROP=`on_remote_exec "get_macsec_counter rx_pkts_drop"`
    fi
}

function read_post_test_counters() {

    if [ "$OFFLOAD_SIDE" == "none" ]; then
        return
    fi

    if [ "$OFFLOAD_SIDE" == "remote" ]; then
        REMOTE_POST_TEST_PKTS_TX=`on_remote_exec "get_macsec_counter tx_pkts"`
        REMOTE_POST_TEST_PKTS_RX=`on_remote_exec "get_macsec_counter rx_pkts"`
        REMOTE_POST_TEST_PKTS_TX_DROP=`on_remote_exec "get_macsec_counter tx_pkts_drop"`
        REMOTE_POST_TEST_PKTS_RX_DROP=`on_remote_exec "get_macsec_counter rx_pkts_drop"`
    elif [ "$OFFLOAD_SIDE" == "local" ]; then
        LOCAL_POST_TEST_PKTS_TX=`get_macsec_counter tx_pkts`
        LOCAL_POST_TEST_PKTS_RX=`get_macsec_counter rx_pkts`
        LOCAL_POST_TEST_PKTS_TX_DROP=`get_macsec_counter tx_pkts_drop`
        LOCAL_POST_TEST_PKTS_RX_DROP=`get_macsec_counter rx_pkts_drop`
    else
        LOCAL_POST_TEST_PKTS_TX=`get_macsec_counter tx_pkts`
        LOCAL_POST_TEST_PKTS_RX=`get_macsec_counter rx_pkts`
        REMOTE_POST_TEST_PKTS_TX=`on_remote_exec "get_macsec_counter tx_pkts"`
        REMOTE_POST_TEST_PKTS_RX=`on_remote_exec "get_macsec_counter rx_pkts"`
        LOCAL_POST_TEST_PKTS_TX_DROP=`get_macsec_counter tx_pkts_drop`
        LOCAL_POST_TEST_PKTS_RX_DROP=`get_macsec_counter rx_pkts_drop`
        REMOTE_POST_TEST_PKTS_TX_DROP=`on_remote_exec "get_macsec_counter tx_pkts_drop"`
        REMOTE_POST_TEST_PKTS_RX_DROP=`on_remote_exec "get_macsec_counter rx_pkts_drop"`
    fi
}

function set_tx_sa() {
    local dev="$1"
    local macsec_dev="$2"
    local sa_to_enable="$3"

    #set tx sa for local
    $MACSEC_CONFIG --device $dev --interface $macsec_dev --enable-sa $sa_to_enable
    $MACSEC_CONFIG --device $dev --interface $macsec_dev --set-encoding-sa $sa_to_enable

    #set tx sa for remote
    on_remote $MACSEC_CONFIG --device $dev --interface $macsec_dev --enable-sa $sa_to_enable
    on_remote $MACSEC_CONFIG --device $dev --interface $macsec_dev --set-encoding-sa $sa_to_enable
}

function verify_offload_counters() {

    if [ "$OFFLOAD_SIDE" == "none" ]; then
        return
    fi

    title "Verify offload"

    #In macsec tests we always send traffic from remote side to local.
    #Since udp is a protocol for data flowing in one direction we can’t
    #expect all counters to advance hence on local side since it's the receiver
    #side we expect RX counters to advance where on remote side since it's transmitter
    #side we expect TX counters to advance.
    if [ "$NET_PROTO" == "udp" ]; then
        if [ "$OFFLOAD_SIDE" == "local" ]; then
            if [[ "$LOCAL_POST_TEST_PKTS_RX" -le "$LOCAL_PRE_TEST_PKTS_RX" ]]; then
                fail "Macsec full offload counters didn't increase as expected on local"
            fi
        elif [ "$OFFLOAD_SIDE" == "remote" ]; then
            if [[ "$REMOTE_POST_TEST_PKTS_TX" -le "$REMOTE_PRE_TEST_PKTS_TX" ]]; then
                fail "Macsec full offload counters didn't increase as expected on remote"
            fi
        else
            if [[ "$LOCAL_POST_TEST_PKTS_RX" -le "$LOCAL_PRE_TEST_PKTS_RX" ]]; then
                fail "Macsec full offload counters didn't increase as expected on local"
            fi
            if [[ "$REMOTE_POST_TEST_PKTS_TX" -le "$REMOTE_PRE_TEST_PKTS_TX" ]]; then
                fail "Macsec full offload counters didn't increase as expected on remote"
            fi
        fi
        return
    fi

    if [ "$OFFLOAD_SIDE" == "local" ]; then
        if [[ "$LOCAL_POST_TEST_PKTS_TX" -le "$LOCAL_PRE_TEST_PKTS_TX" || "$LOCAL_POST_TEST_PKTS_RX" -le "$LOCAL_PRE_TEST_PKTS_RX" ]]; then
            fail "Macsec full offload counters didn't increase as expected on local"
        fi
    elif [ "$OFFLOAD_SIDE" == "remote" ]; then
        if [[ "$REMOTE_POST_TEST_PKTS_TX" -le "$REMOTE_PRE_TEST_PKTS_TX" || "$REMOTE_POST_TEST_PKTS_RX" -le "$REMOTE_PRE_TEST_PKTS_RX" ]]; then
            fail "Macsec full offload counters didn't increase as expected on remote"
        fi
    else
        if [[ "$LOCAL_POST_TEST_PKTS_TX" -le "$LOCAL_PRE_TEST_PKTS_TX" || "$LOCAL_POST_TEST_PKTS_RX" -le "$LOCAL_PRE_TEST_PKTS_RX" ]]; then
            fail "Macsec full offload counters didn't increase as expected on local"
        fi
        if [[ "$REMOTE_POST_TEST_PKTS_TX" -le "$REMOTE_PRE_TEST_PKTS_TX" || "$REMOTE_POST_TEST_PKTS_RX" -le "$REMOTE_PRE_TEST_PKTS_RX" ]]; then
            fail "Macsec full offload counters didn't increase as expected on remote"
        fi
    fi
}

#run_traffic ipv4/ipv6 [udp|tcp|icmp]
function run_traffic() {
    local ip_proto="$1"
    local net_proto="$2"
    local nic=${3:-"$NIC"}
    local expected_traffic=${4:-"have_traffic"}
    local iperf_extra=""
    local tcpdump_exta=""
    local should_err=""

    if [[ "$net_proto" == "tcp" ]]; then
        :
    elif [[ "$net_proto" == "udp" ]]; then
        iperf_extra="-u"
    elif [[ "$net_proto" == "icmp" ]]; then
        :
    else
        err "Wrong arg for function run_traffic"
    fi

    if [[ "$expected_traffic" == "have_traffic" ]]; then
            should_err="err $net_proto traffic failed"
    elif [[ "$expected_traffic" == "no_traffic" ]]; then
            :
    else
        err "Wrong arg for function run_traffic"
    fi

    fail_if_err

    local t=10

    title "Run $net_proto traffic"
    rm -f $TCPDUMP_FILE $IPERF_FILE
    timeout $t tcpdump -qnnei $nic -c 5 -w $TCPDUMP_FILE &
    local upid=$!

    if [[ "$net_proto" == "icmp" ]]; then
        if [[ "$ip_proto" == "ipv4" ]]; then
            (on_remote timeout $((t+2)) ping $MACSEC_LIP -c 7 > /dev/null) || $should_err
        else
            (on_remote timeout $((t+2)) ping $MACSEC_LIP6 -c 7 > /dev/null) || $should_err
        fi
    else
        if [[ "$ip_proto" == "ipv4" ]]; then
            (on_remote timeout $((t+2)) iperf3 -c $MACSEC_LIP $iperf_extra -b 2G --logfile $IPERF_FILE &) || $should_err
        else
            (on_remote timeout $((t+2)) iperf3 -c $MACSEC_LIP6 $iperf_extra -b 2G --logfile $IPERF_FILE &) || $should_err
        fi
    fi

    fail_if_err

    title "Verify $expected_traffic $net_proto on $nic"
    if [[ "$expected_traffic" == "have_traffic" ]]; then
        verify_have_traffic $upid
    else
        verify_no_traffic $upid
    fi
}

function config_macsec_env() {
    macsec_reset_defaults
    enable_legacy
    on_remote_exec enable_legacy
}

function config_macsec() {
    $TESTDIR/macsec-config.sh $@
}

function config_macsec_remote() {
    on_remote $MACSEC_CONFIG $@ --side server
}

function config_keys_and_ips() {
    local ip_proto="$1"
    local macsec_ip_proto="$2"
    local xpn=${3:-"xpn_off"}

    if [ "$ip_proto" == "ipv6" ]; then
        EFFECTIVE_LIP="$LIP6/112"
        EFFECTIVE_RIP="$RIP6/112"
    fi

    if [ "$macsec_ip_proto" == "ipv6" ]; then
        MACSEC_EFFECTIVE_LIP="$MACSEC_LIP6/112"
        MACSEC_EFFECTIVE_RIP="$MACSEC_RIP6/112"
    fi

    if [ "$xpn" == "xpn_on" ]; then
       EFFECTIVE_CIPHER="gcm-aes-xpn-128"
    fi

    if [ "$KEY_LEN" == 256 ]; then
        EFFECTIVE_KEY_IN="$KEY_IN_256"
        EFFECTIVE_KEY_OUT="$KEY_OUT_256"
        if [ "$xpn" == "xpn_on" ]; then
            EFFECTIVE_CIPHER="gcm-aes-xpn-256"
        else
            EFFECTIVE_CIPHER="gcm-aes-256"
        fi
    fi
}

function test_macsec() {
    local dev="$NIC"
    local macsec_dev="macsec0"
    local sa_num="0"
    local sci="$RANDOM"
    local rx_sci="$RANDOM"

    config_keys_and_ips $IP_PROTO $MACSEC_IP_PROTO

    macsec_set_config_extras $@

    config_macsec --device $dev --interface $macsec_dev --cipher $EFFECTIVE_CIPHER \
    --tx-key $EFFECTIVE_KEY_IN --rx-key $EFFECTIVE_KEY_OUT --encoding-sa $sa_num --pn $CLIENT_PN --sci $sci --rx-sci $rx_sci\
    --dev-ip "$EFFECTIVE_LIP" --macsec-ip $MACSEC_EFFECTIVE_LIP $LOCAL_EXTRA

    config_macsec_remote --device $dev --interface $macsec_dev --cipher $EFFECTIVE_CIPHER \
                                       --tx-key $EFFECTIVE_KEY_OUT --rx-key $EFFECTIVE_KEY_IN --encoding-sa $sa_num --pn $SERVER_PN --sci $rx_sci --rx-sci $sci \
                                       --dev-ip $EFFECTIVE_RIP --macsec-ip $MACSEC_EFFECTIVE_RIP $REMOTE_EXTRA

    read_pre_test_counters

    change_mtu_on_both_sides $MTU $dev $macsec_dev

    start_iperf_server

    run_traffic $MACSEC_IP_PROTO $NET_PROTO

    read_post_test_counters

    verify_offload_counters

    kill_iperf
}

function test_macsec_multi_sa() {
    local dev="$NIC"
    local macsec_dev="macsec0"
    local i

    test_macsec --add-multi-sa --xpn $XPN

    start_iperf_server

    for i in 0 1 2 3; do
        title "Multi SA $i"
        set_tx_sa $dev $macsec_dev $i
        change_mtu_on_both_sides $MTU $dev $macsec_dev

        read_pre_test_counters

        run_traffic $MACSEC_IP_PROTO $NET_PROTO

        read_post_test_counters

        verify_offload_counters

    done

    kill_iperf
}

function test_macsec_xpn() {
    local dev="$NIC"
    local macsec_dev="macsec0"
    local multi_sa="off"
    local sa_num="0"
    local sci="$RANDOM"
    local rx_sci="$RANDOM"

    config_keys_and_ips $IP_PROTO $MACSEC_IP_PROTO xpn_on

    macsec_set_config_extras $@

    config_macsec --device $dev --interface $macsec_dev --cipher $EFFECTIVE_CIPHER \
    --tx-key $EFFECTIVE_KEY_IN --rx-key $EFFECTIVE_KEY_OUT --encoding-sa $sa_num --pn $CLIENT_PN --sci $sci --rx-sci $rx_sci\
    --dev-ip "$EFFECTIVE_LIP" --macsec-ip $MACSEC_EFFECTIVE_LIP $LOCAL_EXTRA --xpn on --replay on --window 32

    config_macsec_remote --device $dev --interface $macsec_dev --cipher $EFFECTIVE_CIPHER \
                                       --tx-key $EFFECTIVE_KEY_OUT --rx-key $EFFECTIVE_KEY_IN --encoding-sa $sa_num --pn $SERVER_PN --sci $rx_sci --rx-sci $sci \
                                       --dev-ip $EFFECTIVE_RIP --macsec-ip $MACSEC_EFFECTIVE_RIP $REMOTE_EXTRA --xpn on --replay on --window 32

    read_pre_test_counters

    change_mtu_on_both_sides $MTU $dev $macsec_dev

    start_iperf_server

    run_traffic $MACSEC_IP_PROTO $NET_PROTO

    read_post_test_counters

    verify_offload_counters

    kill_iperf
}

# Usage --mtu <mtu> --ip-proto <ip_proto> --macsec-ip-proto <macsec_ip_proto> --net-proto <net_proto> --offload-side <offload> --multi-sa [multi_sa] --xpn [xpn]
# mtu = {1500..9000}
# ip_proto = ipv4/ipv6
# macsec_ip_proto = ipv4/ipv6
# net_proto = tcp/udp/icmp
# offload_side = local/remote/both/none
# multi_sa = on/off
# xpn = on/off
function run_test_macsec() {
    local len

    macsec_parse_test $@

    for len in 256 128; do
        macsec_cleanup
        macsec_set_key_len $len

        title "Test MACSEC multi_sa=$MULTI_SA, mtu=$MTU, ip_protocol=$IP_PROTO, macsec_ip_protocol=$MACSEC_IP_PROTO, network_protocol=$NET_PROTO, key_length=$len, offload_side=$OFFLOAD_SIDE, xpn=$XPN"

        if [[ "$MULTI_SA" == "on" ]]; then
            test_macsec_multi_sa
            # the following echo is to separate between different iterations prints (by starting a new line) during the test
            echo
        elif [[ "$XPN" = "on" ]]; then
            test_macsec_xpn
            echo
        else
            test_macsec
            echo
        fi
    done
}
