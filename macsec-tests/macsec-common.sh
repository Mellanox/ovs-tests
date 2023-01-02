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

LOCAL_PRE_TEST_PKTS_TX=""
LOCAL_PRE_TEST_PKTS_RX=""
LOCAL_POST_TEST_PKTS_TX=""
LOCAL_POST_TEST_PKTS_RX=""
LOCAL_PRE_TEST_PKTS_TX_DROP=""
LOCAL_PRE_TEST_PKTS_RX_DROP=""
LOCAL_POST_TEST_PKTS_TX_DROP=""
LOCAL_POST_TEST_PKTS_RX_DROP=""

REMOTE_PRE_TEST_PKTS_TX=""
REMOTE_PRE_TEST_PKTS_RX=""
REMOTE_POST_TEST_PKTS_TX=""
REMOTE_POST_TEST_PKTS_RX=""
REMOTE_PRE_TEST_PKTS_TX_DROP=""
REMOTE_PRE_TEST_PKTS_RX_DROP=""
REMOTE_POST_TEST_PKTS_TX_DROP=""
REMOTE_POST_TEST_PKTS_RX_DROP=""

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
    local side=${1:-"both"}

    if [ "$side" == "none" ]; then
        return
    fi

    if [ "$side" == "remote" ]; then
        REMOTE_PRE_TEST_PKTS_TX=`on_remote_exec "get_macsec_counter tx_pkts"`
        REMOTE_PRE_TEST_PKTS_RX=`on_remote_exec "get_macsec_counter rx_pkts"`
        REMOTE_PRE_TEST_PKTS_TX_DROP=`on_remote_exec "get_macsec_counter tx_pkts_drop"`
        REMOTE_PRE_TEST_PKTS_RX_DROP=`on_remote_exec "get_macsec_counter rx_pkts_drop"`
    elif [ "$side" == "local" ]; then
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
    local side=${1:-"both"}

    if [ "$side" == "none" ]; then
        return
    fi

    if [ "$side" == "remote" ]; then
        REMOTE_POST_TEST_PKTS_TX=`on_remote_exec "get_macsec_counter tx_pkts"`
        REMOTE_POST_TEST_PKTS_RX=`on_remote_exec "get_macsec_counter rx_pkts"`
        REMOTE_POST_TEST_PKTS_TX_DROP=`on_remote_exec "get_macsec_counter tx_pkts_drop"`
        REMOTE_POST_TEST_PKTS_RX_DROP=`on_remote_exec "get_macsec_counter rx_pkts_drop"`
    elif [ "$side" == "local" ]; then
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
    local side=${1:-"both"}
    local net_proto=$2

    if [ "$side" == "none" ]; then
        return
    fi

    title "Verify offload"

    #In macsec tests we always send traffic from remote side to local.
    #Since udp is a protocol for data flowing in one direction we can’t
    #expect all counters to advance hence on local side since it's the receiver
    #side we expect RX counters to advance where on remote side since it's transmitter
    #side we expect TX counters to advance.
    if [ "$net_proto" == "udp" ]; then
        if [ "$side" == "local" ]; then
            if [[ "$LOCAL_POST_TEST_PKTS_RX" -le "$LOCAL_PRE_TEST_PKTS_RX" ]]; then
                fail "Macsec full offload counters didn't increase as expected on local"
            fi
        elif [ "$side" == "remote" ]; then
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

    if [ "$side" == "local" ]; then
        if [[ "$LOCAL_POST_TEST_PKTS_TX" -le "$LOCAL_PRE_TEST_PKTS_TX" || "$LOCAL_POST_TEST_PKTS_RX" -le "$LOCAL_PRE_TEST_PKTS_RX" ]]; then
            fail "Macsec full offload counters didn't increase as expected on local"
        fi
    elif [ "$side" == "remote" ]; then
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
    local key_len="$3"
    local xpn=${4:-"xpn_off"}

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

    if [ "$key_len" == 256 ]; then
        EFFECTIVE_KEY_IN="$KEY_IN_256"
        EFFECTIVE_KEY_OUT="$KEY_OUT_256"
        if [ "$xpn" == "xpn_on" ]; then
            EFFECTIVE_CIPHER="gcm-aes-xpn-256"
        else
            EFFECTIVE_CIPHER="gcm-aes-256"
        fi
    fi
}

# Usage <mtu> <ip_proto> <macsec_ip_proto> <key_len> <net_proto> <offload_side> [--add-multi-sa]
# mtu = {1500..9000}
# ip_proto = ipv4/ipv6
# macsec_ip_proto= ipv4/ipv6
# key_len = 128/256
# net_proto = tcp/udp/icmp
# offload_side = local/remote/both/none
function test_macsec() {
    local mtu="$1"
    local ip_proto="$2"
    local macsec_ip_proto="$3"
    local key_len="$4"
    local net_proto="$5"
    local offload_side=$6
    local dev="$NIC"
    local macsec_dev="macsec0"
    local sa_num="0"
    local client_pn=$(($RANDOM % 10000))
    local server_pn=$(($RANDOM % 10000))
    local sci="$RANDOM"
    local rx_sci="$RANDOM"
    local local_extra=""
    local remote_extra=""

    # Pass rest of the args as params.
    shift 6

    if [ "$offload_side" == "local" ]; then
        local_extra="$local_extra --offload $@"
        remote_extra="$remote_extra $@"
    elif [ "$offload_side" == "remote" ]; then
        local_extra="$local_extra $@"
        remote_extra="$remote_extra --offload $@"
    elif [ "$offload_side" == "both" ]; then
        local_extra="$local_extra --offload $@"
        remote_extra="$remote_extra --offload $@"
    elif [ "$offload_side" == "none" ]; then
        local_extra="$local_extra $@"
        remote_extra="$remote_extra $@"
    else
        err "$offload_side is not a valid value for offload_side parameter"
    fi

    config_keys_and_ips $ip_proto $macsec_ip_proto $key_len

    config_macsec --device $dev --interface $macsec_dev --cipher $EFFECTIVE_CIPHER \
    --tx-key $EFFECTIVE_KEY_IN --rx-key $EFFECTIVE_KEY_OUT --encoding-sa $sa_num --pn $client_pn --sci $sci --rx-sci $rx_sci\
    --dev-ip "$EFFECTIVE_LIP" --macsec-ip $MACSEC_EFFECTIVE_LIP $local_extra

    config_macsec_remote --device $dev --interface $macsec_dev --cipher $EFFECTIVE_CIPHER \
                                       --tx-key $EFFECTIVE_KEY_OUT --rx-key $EFFECTIVE_KEY_IN --encoding-sa $sa_num --pn $server_pn --sci $rx_sci --rx-sci $sci \
                                       --dev-ip $EFFECTIVE_RIP --macsec-ip $MACSEC_EFFECTIVE_RIP $remote_extra

    read_pre_test_counters $offload_side

    change_mtu_on_both_sides $mtu $dev $macsec_dev

    start_iperf_server

    run_traffic $macsec_ip_proto $net_proto

    read_post_test_counters $offload_side

    verify_offload_counters $offload_side $net_proto

    kill_iperf
}

function test_macsec_multi_sa() {
    local mtu="$1"
    local ip_proto="$2"
    local macsec_ip_proto="$3"
    local key_len="$4"
    local net_proto="$5"
    local offload_side="$6"
    local xpn="$7"
    local dev="$NIC"
    local macsec_dev="macsec0"
    local i

    if [[ "$xpn" == "on" ]]; then
        xpn="--xpn on"
    fi

    test_macsec $mtu $ip_proto $macsec_ip_proto $key_len $net_proto $offload_side --add-multi-sa $xpn

    start_iperf_server

    for i in 0 1 2 3; do
        title "Test MACSEC with Multi SAs with mtu = $mtu , ip_protocol = $ip_proto ,  macsec_ip_protocol = $macsec_ip_proto ,network_protocol = $net_proto , key length = $len and offload = $offload_side using SA $i"
        set_tx_sa $dev $macsec_dev $i
        change_mtu_on_both_sides $mtu $dev $macsec_dev

        read_pre_test_counters $offload_side

        run_traffic $macsec_ip_proto $net_proto

        read_post_test_counters $offload_side

        verify_offload_counters $offload_side $net_proto

    done

    kill_iperf
}

function test_macsec_xpn() {
    local mtu="$1"
    local ip_proto="$2"
    local macsec_ip_proto="$3"
    local key_len="$4"
    local net_proto="$5"
    local offload_side="$6"
    local dev="$NIC"
    local macsec_dev="macsec0"
    local multi_sa="off"
    local sa_num="0"
    local client_pn=4294967290
    local server_pn=4294967290
    local sci="$RANDOM"
    local rx_sci="$RANDOM"
    local local_extra=""
    local remote_extra=""

    config_keys_and_ips $ip_proto $macsec_ip_proto $key_len xpn_on

    if [ "$offload_side" == "both" ]; then
        local_extra="$local_extra --offload"
        remote_extra="$remote_extra --offload"
    fi

    config_macsec --device $dev --interface $macsec_dev --cipher $EFFECTIVE_CIPHER \
    --tx-key $EFFECTIVE_KEY_IN --rx-key $EFFECTIVE_KEY_OUT --encoding-sa $sa_num --pn $client_pn --sci $sci --rx-sci $rx_sci\
    --dev-ip "$EFFECTIVE_LIP" --macsec-ip $MACSEC_EFFECTIVE_LIP $local_extra --xpn on --replay on --window 32

    config_macsec_remote --device $dev --interface $macsec_dev --cipher $EFFECTIVE_CIPHER \
                                       --tx-key $EFFECTIVE_KEY_OUT --rx-key $EFFECTIVE_KEY_IN --encoding-sa $sa_num --pn $server_pn --sci $rx_sci --rx-sci $sci \
                                       --dev-ip $EFFECTIVE_RIP --macsec-ip $MACSEC_EFFECTIVE_RIP $remote_extra --xpn on --replay on --window 32

    read_pre_test_counters $offload_side

    change_mtu_on_both_sides $mtu $dev $macsec_dev

    start_iperf_server

    run_traffic $macsec_ip_proto $net_proto

    read_post_test_counters $offload_side

    verify_offload_counters $offload_side $net_proto

    kill_iperf
}

# Usage <mtu> <ip_proto> <macsec_ip_proto> <net_proto> <offload> [multi_sa]
# mtu = {1500..9000}
# ip_proto = ipv4/ipv6
# macsec_ip_proto = ipv4/ipv6
# net_proto = tcp/udp/icmp
# offload_side = local/remote/both/none
# multi_sa = on/off
# xpn = on/off
function run_test_macsec() {
    local mtu=$1
    local ip_proto="$2"
    local macsec_ip_proto="$3"
    local net_proto="$4"
    local offload_side="$5"
    local multi_sa=${6:-"off"}
    local xpn=${7:-"off"}
    local len

    for len in 256 128; do
        macsec_cleanup
        if [[ "$multi_sa" == "on" ]]; then
            title "Test MACSEC with Multi SAs with mtu = $mtu , ip_protocol = $ip_proto ,  macsec_ip_protocol = $macsec_ip_proto ,network_protocol = $net_proto , key length = $len and offload = $offload_side , xpn = $xpn"
            test_macsec_multi_sa $mtu $ip_proto $macsec_ip_proto $len $net_proto $offload_side $xpn
            # the following echo is to separate between different iterations prints (by starting a new line) during the test
            echo
        elif [[ "$xpn" = "on" ]]; then
            title "Test MACSEC with ip_protocol = $ip_proto ,  macsec_ip_protocol = $macsec_ip_proto ,network_protocol = $net_proto , key length = $len xpn = on, offload = $offload_side"
            test_macsec_xpn $mtu $ip_proto $macsec_ip_proto $len $net_proto $offload_side
            echo
        else
            title "Test MACSEC with mtu = $mtu , ip_protocol = $ip_proto ,  macsec_ip_protocol = $macsec_ip_proto ,network_protocol = $net_proto , key length = $len and offload = $offload_side"
            test_macsec $mtu $ip_proto $macsec_ip_proto $len $net_proto $offload_side
            echo
        fi
    done
}
