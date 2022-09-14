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

REMOTE_PRE_TEST_PKTS_TX=""
REMOTE_PRE_TEST_PKTS_RX=""
REMOTE_POST_TEST_PKTS_TX=""
REMOTE_POST_TEST_PKTS_RX=""

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

function macsec_cleanup() {
    local mtu=${1:-"1500"}
    local dev=${2:-"$NIC"}
    local macsec_dev=${3:-"macsec0"}
    macsec_cleanup_local $dev $macsec_dev
    macsec_cleanup_remote $dev $macsec_dev
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
    local counter_name="$1"
    local dev=${2:-"$NIC"}
    local res

    if [[ "$counter_name" != "tx" &&  "$counter_name" != "rx" ]]; then
        err "Wrong argument for function get_macsec_counter"
    fi

    res=`ethtool -S $dev | grep "macsec_${counter_name}_pkts:" | awk '{print $2}'`
    echo $res
}

function get_macsec_counter_on_remote() {
    local counter_name="$1"
    local dev=${2:-"$NIC"}

    on_remote_exec "get_macsec_counter $counter_name $dev"
}

function read_pre_test_counters() {
    local side=${1:-"both"}

    if [ "$side" == "remote" ]; then
        REMOTE_PRE_TEST_PKTS_TX=`on_remote_exec "get_macsec_counter tx"`
        REMOTE_PRE_TEST_PKTS_RX=`on_remote_exec "get_macsec_counter rx"`
    elif [ "$side" == "local" ]; then
        LOCAL_PRE_TEST_PKTS_TX=`get_macsec_counter tx`
        LOCAL_PRE_TEST_PKTS_RX=`get_macsec_counter rx`
    else
        LOCAL_PRE_TEST_PKTS_TX=`get_macsec_counter tx`
        LOCAL_PRE_TEST_PKTS_RX=`get_macsec_counter rx`
        REMOTE_PRE_TEST_PKTS_TX=`on_remote_exec "get_macsec_counter tx"`
        REMOTE_PRE_TEST_PKTS_RX=`on_remote_exec "get_macsec_counter rx"`
    fi
}

function read_post_test_counters() {
    local side=${1:-"both"}

    if [ "$side" == "remote" ]; then
        REMOTE_POST_TEST_PKTS_TX=`on_remote_exec "get_macsec_counter tx"`
        REMOTE_POST_TEST_PKTS_RX=`on_remote_exec "get_macsec_counter rx"`
    elif [ "$side" == "local" ]; then
        LOCAL_POST_TEST_PKTS_TX=`get_macsec_counter tx`
        LOCAL_POST_TEST_PKTS_RX=`get_macsec_counter rx`
    else
        LOCAL_POST_TEST_PKTS_TX=`get_macsec_counter tx`
        LOCAL_POST_TEST_PKTS_RX=`get_macsec_counter rx`
        REMOTE_POST_TEST_PKTS_TX=`on_remote_exec "get_macsec_counter tx"`
        REMOTE_POST_TEST_PKTS_RX=`on_remote_exec "get_macsec_counter rx"`
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

function verify_offload() {
    local side=${1:-"both"}
    title "Verify offload"

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
    local iperf_extra=""
    local tcpdump_exta=""

    if [[ "$net_proto" == "tcp" ]]; then
        :
    elif [[ "$net_proto" == "udp" ]]; then
        iperf_extra="-u"
    elif [[ "$net_proto" == "icmp" ]]; then
        :
    else
        err "Wrong arg for function run_traffic"
    fi

    local t=10

    title "Run $net_proto traffic"
    rm -f $TCPDUMP_FILE $IPERF_FILE
    start_iperf_server
    timeout $t tcpdump -qnnei $nic -c 5 -w $TCPDUMP_FILE &
    local upid=$!

    if [[ "$net_proto" == "icmp" ]]; then
        if [[ "$ip_proto" == "ipv4" ]]; then
            (on_remote timeout $((t+2)) ping $MACSEC_LIP -c 7 > /dev/null) || err "ping failed"
        else
            (on_remote timeout $((t+2)) ping $MACSEC_LIP6 -c 7 > /dev/null) || err "ping failed"
        fi
    else
        if [[ "$ip_proto" == "ipv4" ]]; then
            (on_remote timeout $((t+2)) iperf3 -c $MACSEC_LIP $iperf_extra -b 2G --logfile $IPERF_FILE &) || err "iperf3 failed"
        else
            (on_remote timeout $((t+2)) iperf3 -c $MACSEC_LIP6 $iperf_extra -b 2G --logfile $IPERF_FILE &) || err "iperf3 failed"
        fi
    fi

    fail_if_err

    title "Verify $net_proto traffic on $nic"
    verify_have_traffic $upid
}

function config_macsec_env() {
    enable_legacy
    on_remote_exec enable_legacy
}

function config_macsec() {
    local encrypt="$1"
    local ip_proto="$2"
    local macsec_ip_proto="$3"
    local key_len="$4"
    local net_proto="$5"
    local offload="$6"
    local dev="$7"
    local macsec_dev="$8"
    local sa_num="$9"
    local client_pn="${10}"
    local server_pn="${11}"
    local sci="${12}"
    local rx_sci="${13}"
    local multi_sa="${14}"
    local one_offload_side=${15:-"dont_use"} #local/remote/dont_use
    local local_extra=""
    local remote_extra=""
    local effective_lip="$LIP/24"
    local effective_rip="$RIP/24"
    local macsec_effective_lip="$MACSEC_LIP/24"
    local macsec_effective_rip="$MACSEC_RIP/24"
    local effective_cipher="gcm-aes-128"
    local effective_key_in="$KEY_IN_128"
    local effective_key_out="$KEY_OUT_128"

    if [ "$offload" == "mac" ]; then
        local_extra="--offload"
        remote_extra="--offload"
    fi

    if [ "$one_offload_side" == "local" ]; then
            local_extra="--offload"
            remote_extra=""
    elif [ "$one_offload_side" == "remote" ]; then
            local_extra=""
            remote_extra="--offload"
    fi

    if [ "$multi_sa" == "on" ]; then
        local_extra="$local_extra --add-multi-sa"
        remote_extra="$remote_extra --add-multi-sa"
    fi

    if [ "$ip_proto" == "ipv6" ]; then
        effective_lip="$LIP6/112"
        effective_rip="$RIP6/112"
    fi

    if [ "$macsec_ip_proto" == "ipv6" ]; then
        macsec_effective_lip="$MACSEC_LIP6/112"
        macsec_effective_rip="$MACSEC_RIP6/112"
    fi

    if [ "$key_len" == 256 ]; then
        effective_key_in="$KEY_IN_256"
        effective_key_out="$KEY_OUT_256"
        effective_cipher="gcm-aes-256"
    fi

    #Config local
    $TESTDIR/macsec-config.sh --device $dev --interface $macsec_dev --encrypt $encrypt --cipher $effective_cipher \
    --tx-key $effective_key_in --rx-key $effective_key_out --encoding-sa $sa_num --pn $client_pn --sci $sci --rx-sci $rx_sci\
    --dev-ip "$effective_lip" --macsec-ip $macsec_effective_lip $local_extra

    #Config remote
    ssh2 $REMOTE_SERVER "bash -s" -- < $TESTDIR/macsec-config.sh --device $dev --interface $macsec_dev --encrypt $encrypt --cipher $effective_cipher \
                                       --tx-key $effective_key_out --rx-key $effective_key_in --encoding-sa $sa_num --pn $server_pn --sci $rx_sci --rx-sci $sci \
                                       --dev-ip $effective_rip --macsec-ip $macsec_effective_rip --side server $remote_extra
}

# Usage <mtu> <encrypt> <ip_proto> <macsec_ip_proto> <key_len> <net_proto> <offload> [multi_sa] [dev] [macsec_dev]
# mtu = {1500..9000}
# encrypt = on/off
# ip_proto = ipv4/ipv6
# macsec_ip_proto= ipv4/ipv6
# key_len = 128/256
# net_proto = tcp/udp/icmp
# offload = off/mac
# multi_sa= = on/off
# dev = <interface>
# macsec_dev = <macsec_interface>
function test_macsec() {
    local mtu="$1"
    local encrypt="$2"
    local ip_proto="$3"
    local macsec_ip_proto="$4"
    local key_len="$5"
    local net_proto="$6"
    local offload="$7"
    local multi_sa=${8:-"off"}
    local dev=${9:-"$NIC"}
    local macsec_dev=${10:-"macsec0"}
    local sa_num="0"
    local client_pn=$(($RANDOM % 10000))
    local server_pn=$(($RANDOM % 10000))
    local sci="$RANDOM"
    local rx_sci="$RANDOM"

    config_macsec $encrypt $ip_proto $macsec_ip_proto $key_len $net_proto $offload $dev $macsec_dev $sa_num $client_pn $server_pn $sci $rx_sci $multi_sa

    if [[ "$offload" == "mac" ]]; then
        read_pre_test_counters
    fi

    change_mtu_on_both_sides $mtu $dev $macsec_dev
    run_traffic $macsec_ip_proto $net_proto

    if [[ "$offload" == "mac" ]]; then
        read_post_test_counters
        verify_offload
    fi
}

function test_macsec_one_side_offload() {
    local mtu="$1"
    local encrypt="$2"
    local ip_proto="$3"
    local macsec_ip_proto="$4"
    local key_len="$5"
    local net_proto="$6"
    local offload="$7"
    local one_side_offload=${8:-"local"}
    local dev=${9:-"$NIC"}
    local macsec_dev=${10:-"macsec0"}
    local sa_num="0"
    local client_pn=$(($RANDOM % 10000))
    local server_pn=$(($RANDOM % 10000))
    local sci="$RANDOM"
    local rx_sci="$RANDOM"

    config_macsec $encrypt $ip_proto $macsec_ip_proto $key_len $net_proto $offload $dev $macsec_dev $sa_num $client_pn $server_pn $sci $rx_sci off $one_side_offload

    if [[ "$one_side_offload" == "local" ]]; then
        read_pre_test_counters local
    elif [[ "$one_side_offload" == "remote" ]]; then
        read_pre_test_counters remote
    else
        err "$one_side_offload is not a valid value for one_side_offload parameter"
    fi

    change_mtu_on_both_sides $mtu $dev $macsec_dev
    run_traffic $macsec_ip_proto $net_proto


    if [[ "$one_side_offload" == "local" ]]; then
        read_post_test_counters local
        verify_offload local
    elif [[ "$one_side_offload" == "remote" ]]; then
        read_post_test_counters remote
        verify_offload remote
    else
        err "$one_side_offload is not a valid value for one_side_offload parameter"
    fi
}

function test_macsec_multi_sa() {
    local mtu="$1"
    local encrypt="$2"
    local ip_proto="$3"
    local macsec_ip_proto="$4"
    local key_len="$5"
    local net_proto="$6"
    local offload="$7"
    local dev=${8:-"$NIC"}
    local macsec_dev=${9:-"macsec0"}
    local i

    test_macsec $mtu $encrypt $ip_proto $macsec_ip_proto $key_len $net_proto $offload on

    for i in 0 1 2 3; do
        title "Test MACSEC with Multi SAs with mtu = $mtu , encrypt = $encrypt , ip_protocol = $ip_proto ,  macsec_ip_protocol = $macsec_ip_proto ,network_protocol = $net_proto , key length = $len and offload = $offload using SA $i"
        set_tx_sa $dev $macsec_dev $i
        change_mtu_on_both_sides $mtu $dev $macsec_dev

        if [[ "$offload" == "mac" ]]; then
            read_pre_test_counters
        fi

        run_traffic $macsec_ip_proto $net_proto

        if [[ "$offload" == "mac" ]]; then
            read_post_test_counters
            verify_offload
        fi
    done
}

# Usage <mtu> <encrypt> <ip_proto> <macsec_ip_proto> <net_proto> <offload> [multi_sa] [local one_side_offload]
# mtu = {1500..9000}
# encrypt = on/off
# ip_proto = ipv4/ipv6
# macsec_ip_proto = ipv4/ipv6
# net_proto = tcp/udp/icmp
# offload = off/mac - off = no offload
# multi_sa = on/off
# one_side_offloadd = local/remote/dont_use
function run_test_macsec() {
    local mtu=$1
    local encrypt="$2"
    local ip_proto="$3"
    local macsec_ip_proto="$4"
    local net_proto="$5"
    local offload="$6"
    local multi_sa=${7:-"off"}
    local one_side_offload=${8:-"dont_use"}
    local len

    for len in 256 128; do
        macsec_cleanup
        if [[ "$multi_sa" == "on" ]]; then
            title "Test MACSEC with Multi SAs with mtu = $mtu , encrypt = $encrypt , ip_protocol = $ip_proto ,  macsec_ip_protocol = $macsec_ip_proto ,network_protocol = $net_proto , key length = $len and offload = $offload"
            test_macsec_multi_sa $mtu $encrypt $ip_proto $macsec_ip_proto $len $net_proto $offload
            # the following echo is to separate between different iterations prints (by starting a new line) during the test
            echo
        elif [[ "$one_side_offload" = "local" ]]; then
            title "Test MACSEC with mtu = $mtu , encrypt = $encrypt , ip_protocol = $ip_proto ,  macsec_ip_protocol = $macsec_ip_proto ,network_protocol = $net_proto , key length = $len and offload = only RX offloaded"
            test_macsec_one_side_offload $mtu $encrypt $ip_proto $macsec_ip_proto $len $net_proto $offload local
            echo
        elif [[ "$one_side_offload" = "remote" ]]; then
            title "Test MACSEC with mtu = $mtu , encrypt = $encrypt , ip_protocol = $ip_proto ,  macsec_ip_protocol = $macsec_ip_proto ,network_protocol = $net_proto , key length = $len and offload = only TX offloaded"
            test_macsec_one_side_offload $mtu $encrypt $ip_proto $macsec_ip_proto $len $net_proto $offload remote
            echo
        else
            title "Test MACSEC with mtu = $mtu , encrypt = $encrypt , ip_protocol = $ip_proto ,  macsec_ip_protocol = $macsec_ip_proto ,network_protocol = $net_proto , key length = $len and offload = $offload"
            test_macsec $mtu $encrypt $ip_proto $macsec_ip_proto $len $net_proto $offload
            echo
        fi
    done
}
