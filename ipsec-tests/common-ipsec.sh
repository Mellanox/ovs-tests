#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/../common.sh

LIP="172.16.0.1"
RIP="172.16.0.2"
LIP6="2001:192:168:211::64"
RIP6="2001:192:168:211::65"

require_cmd xxd

function require_ip_xfrm() {
    ip xfrm state &>/dev/null || fail "ipsec is not supported"
}

function require_ipsec_mode() {
    if [ ! -f "/sys/class/net/$NIC/compat/devlink/ipsec_mode" ]; then
        fail "Unsupported Kernel for IPsec full offload"
    fi
}

require_ip_xfrm

#KEYMAT 20 octets = KEY 16ocets, SALT 4octets
#128 refers to the KEY without the SALT.
KEY_IN_128=0x`dd if=/dev/urandom count=20 bs=1 2> /dev/null| xxd -p -c 40`
KEY_OUT_128=0x`dd if=/dev/urandom count=20 bs=1 2> /dev/null| xxd -p -c 40`
#KEYMAT 36 octets = KEY 32ocets, SALT 4octets
#256 refers to the KEY without the SALT.
KEY_IN_256=0x`dd if=/dev/urandom count=36 bs=1 2> /dev/null| xxd -p -c 72`
KEY_OUT_256=0x`dd if=/dev/urandom count=36 bs=1 2> /dev/null| xxd -p -c 72`

# Usage <MODE> <IPSEC_MODE> <KEY_LEN> <IP_PROTO> [offload]
# MODE = local|remote
# IPSEC_MODE = transport|tunnel
# KEY_LEN = 128|256
# IP_PROTO = ipv4|ipv6
# SHOULD_OFFLOAD = [offload]
function ipsec_config() {
    local MODE="$1"
    local IPSEC_MODE="$2"
    local KEY_LEN="$3"
    local IP_PROTO="$4"
    local SHOULD_OFFLOAD="$5"  #SHOULD_OFFLOAD will be equal to "" if no offload
    local EFFECTIVE_LIP=$LIP
    local EFFECTIVE_RIP=$RIP

    if [[ "$MODE" == "local" ]]; then
        local nic=$NIC
        local IP=$LIP
        local IP6=$LIP6
    elif [[ "$MODE" == "remote" ]]; then #when on remote packet direction is the opposite (what's going out from local is going in on remote)
        local nic=$REMOTE_NIC
        local IP=$RIP
        local IP6=$RIP6
    else
        fail "Wrong usage, MODE local|remote"
    fi

    if [[ "$IPSEC_MODE" != "transport" && "$IPSEC_MODE" != "tunnel" ]]; then
        fail "Wrong usage, IPSEC_MODE transport|tunnel"
    fi

    if [[ "$IP_PROTO" != "ipv4" && "$IP_PROTO" != "ipv6" ]]; then
        fail "Wrong usage, IP_PROTO ipv4|ipv6"
    fi

    if [[ "$KEY_LEN" == 128 ]]; then
    if [[ "$MODE" == "local" ]]; then
        local ALGO_LINE_IN="aead rfc4106(gcm(aes)) $KEY_IN_128 128"
            local ALGO_LINE_OUT="aead rfc4106(gcm(aes)) $KEY_OUT_128 128"
    else
            local ALGO_LINE_IN="aead 'rfc4106(gcm(aes))' $KEY_IN_128 128"
            local ALGO_LINE_OUT="aead 'rfc4106(gcm(aes))' $KEY_OUT_128 128"
        fi
    elif [[ "$KEY_LEN" == 256 ]]; then
        if [[ "$MODE" == "local" ]]; then
        local ALGO_LINE_IN="aead rfc4106(gcm(aes)) $KEY_IN_256 128"
            local ALGO_LINE_OUT="aead rfc4106(gcm(aes)) $KEY_OUT_256 128"
    else
            local ALGO_LINE_IN="aead 'rfc4106(gcm(aes))' $KEY_IN_256 128"
            local ALGO_LINE_OUT="aead 'rfc4106(gcm(aes))' $KEY_OUT_256 128"
        fi
    else
        fail "Wrong usage, KEY_LEN 128|256"
    fi

    if [ "$SHOULD_OFFLOAD" == "" ]; then
        OFFLOAD_IN=""
        OFFLOAD_OUT=""
    elif [ "$SHOULD_OFFLOAD" == "offload" ]; then
        OFFLOAD_IN="offload dev ${nic} dir in"
        OFFLOAD_OUT="offload dev ${nic} dir out"
    else
        fail "Wrong usage, SHOULD_OFFLOAD [offload]"
    fi

    cmds="ip address flush $nic"

    if [[ "$IP_PROTO" == "ipv6" ]]; then
        EFFECTIVE_LIP=$LIP6
        EFFECTIVE_RIP=$RIP6
        cmds="$cmds
              ip -6 address add ${IP6}/112 dev $nic"
    else
        cmds="$cmds
              ip -4 address add ${IP}/16 dev $nic"
    fi

    cmds="$cmds
          ip link set $nic up"

    if [[ "$MODE" == "local" && "$IPSEC_MODE" == "transport" ]]; then
        ip xfrm state flush
        ip xfrm policy flush
        ip xfrm state add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp spi 1000 reqid 10000 $ALGO_LINE_IN mode $IPSEC_MODE sel src $EFFECTIVE_LIP dst $EFFECTIVE_RIP $OFFLOAD_OUT
        ip xfrm state add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp spi 1001 reqid 10001 $ALGO_LINE_OUT mode $IPSEC_MODE sel src $EFFECTIVE_RIP dst $EFFECTIVE_LIP $OFFLOAD_IN
        ip xfrm policy add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP dir out tmpl src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp reqid 10000 mode $IPSEC_MODE
        ip xfrm policy add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP dir in tmpl src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp reqid 10001 mode $IPSEC_MODE
        ip xfrm policy add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP dir fwd tmpl src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp reqid 10001 mode $IPSEC_MODE
        eval "$cmds"
    elif [[ "$MODE" == "remote" && "$IPSEC_MODE" == "transport" ]]; then
        on_remote "
            ip xfrm state flush
            ip xfrm policy flush
            ip xfrm state add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp spi 1000 reqid 10000 $ALGO_LINE_IN mode $IPSEC_MODE sel src $EFFECTIVE_LIP dst $EFFECTIVE_RIP $OFFLOAD_IN
            ip xfrm state add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp spi 1001 reqid 10001 $ALGO_LINE_OUT mode $IPSEC_MODE sel src $EFFECTIVE_RIP dst $EFFECTIVE_LIP $OFFLOAD_OUT
            ip xfrm policy add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP dir in tmpl src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp reqid 10000 mode $IPSEC_MODE
            ip xfrm policy add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP dir out tmpl src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp reqid 10001 mode $IPSEC_MODE
            ip xfrm policy add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP dir fwd tmpl src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp reqid 10000 mode $IPSEC_MODE"
        on_remote "$cmds"
    elif [[ "$MODE" == "local" && "$IPSEC_MODE" == "tunnel" ]]; then
            eval "$cmds"
            ip xfrm state flush
            ip xfrm policy flush
            ip xfrm state add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp spi 1000 reqid 10000 $ALGO_LINE_IN mode $IPSEC_MODE $OFFLOAD_OUT
            ip xfrm state add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp spi 1001 reqid 10001 $ALGO_LINE_IN mode $IPSEC_MODE $OFFLOAD_IN
            ip xfrm policy add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP dir out tmpl src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp reqid 10000 mode tunnel
            ip xfrm policy add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP dir in tmpl src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp reqid 10001 mode tunnel
            ip xfrm policy add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP dir fwd tmpl src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp reqid 10001 mode tunnel
    elif [[ "$MODE" == "remote" && "$IPSEC_MODE" == "tunnel" ]]; then
        on_remote "$cmds"
        on_remote "ip xfrm state flush
                   ip xfrm policy flush
                   ip xfrm state add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp spi 1000 reqid 10000 $ALGO_LINE_IN mode $IPSEC_MODE $OFFLOAD_IN
                   ip xfrm state add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp spi 1001 reqid 10001 $ALGO_LINE_IN mode $IPSEC_MODE $OFFLOAD_OUT
                   ip xfrm policy add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP dir out tmpl src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp reqid 10001 mode tunnel
                   ip xfrm policy add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP dir in tmpl src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp reqid 10000 mode tunnel
                   ip xfrm policy add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP dir fwd tmpl src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp reqid 10000 mode tunnel"
    else
        fail "Cannot config ipsec mode $MODE ipsec_mode $IPSEC_MODE"
    fi
}

function ipsec_config_local() {
    local IPSEC_MODE="$1"
    local KEY_LEN="$2"
    local IP_PROTO="$3"
    local SHOULD_OFFLOAD="$4"

    ipsec_config local $IPSEC_MODE $KEY_LEN $IP_PROTO $SHOULD_OFFLOAD
}

function ipsec_config_remote() {
    local IPSEC_MODE="$1"
    local KEY_LEN="$2"
    local IP_PROTO="$3"
    local SHOULD_OFFLOAD="$4"

    ipsec_config remote $IPSEC_MODE $KEY_LEN $IP_PROTO $SHOULD_OFFLOAD
}

function ipsec_config_on_both_sides() {
    local IPSEC_MODE="$1"
    local KEY_LEN="$2"
    local IP_PROTO="$3"
    local SHOULD_OFFLOAD="$4"

    ipsec_config_local $IPSEC_MODE $KEY_LEN $IP_PROTO $SHOULD_OFFLOAD
    ipsec_config_remote $IPSEC_MODE $KEY_LEN $IP_PROTO $SHOULD_OFFLOAD
}

function ipsec_clean_up_local() {
    ip xfrm state flush
    ip xfrm policy flush
    ip address flush $NIC
}

function ipsec_clean_up_remote() {
    on_remote "ip xfrm state flush
               ip xfrm policy flush
               ip address flush $REMOTE_NIC"
}

function ipsec_clean_up_on_both_sides() {
    ipsec_clean_up_local
    ipsec_clean_up_remote
}

function change_mtu_on_both_sides() {
    local mtu_val=${1:-1500}
    ip link set $NIC mtu $mtu_val
    on_remote ip link set $REMOTE_NIC mtu $mtu_val
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

function ipsec_set_mode() {
    local mode=$1
    echo $mode > /sys/class/net/$NIC/compat/devlink/ipsec_mode || err "Failed to set ipsec mode $mode"
}

function ipsec_get_mode() {
    cat /sys/class/net/$NIC/compat/devlink/ipsec_mode
}
