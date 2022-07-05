IPSEC_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
. $IPSEC_DIR/../common.sh
. $IPSEC_DIR/common-ipsec-offload.sh

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
# MODE = local|remote|local_vf|remote_vf
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
    elif [[ "$MODE" == "local_vf" ]]; then
        local nic=$VF
        local IP=$LIP
        local IP6=$LIP6
    elif [[ "$MODE" == "remote_vf" ]]; then
        local nic=$VF
        local IP=$RIP
        local IP6=$RIP6
    else
        fail "Wrong usage, MODE local|remote|local_vf|remote_vf"
    fi

    if [[ "$IPSEC_MODE" != "transport" && "$IPSEC_MODE" != "tunnel" ]]; then
        fail "Wrong usage, IPSEC_MODE transport|tunnel"
    fi

    if [[ "$IP_PROTO" != "ipv4" && "$IP_PROTO" != "ipv6" ]]; then
        fail "Wrong usage, IP_PROTO ipv4|ipv6"
    fi

    if [[ "$KEY_LEN" == 128 ]]; then
        if [[ "$MODE" == "local" || "$MODE" == "local_vf" ]]; then
            local ALGO_LINE_IN="aead rfc4106(gcm(aes)) $KEY_IN_128 128"
            local ALGO_LINE_OUT="aead rfc4106(gcm(aes)) $KEY_OUT_128 128"
        else
            local ALGO_LINE_IN="aead 'rfc4106(gcm(aes))' $KEY_IN_128 128"
            local ALGO_LINE_OUT="aead 'rfc4106(gcm(aes))' $KEY_OUT_128 128"
        fi
    elif [[ "$KEY_LEN" == 256 ]]; then
        if [[ "$MODE" == "local" ||  "$MODE" == "local_vf" ]]; then
            local ALGO_LINE_IN="aead rfc4106(gcm(aes)) $KEY_IN_256 128"
            local ALGO_LINE_OUT="aead rfc4106(gcm(aes)) $KEY_OUT_256 128"
        else
            local ALGO_LINE_IN="aead 'rfc4106(gcm(aes))' $KEY_IN_256 128"
            local ALGO_LINE_OUT="aead 'rfc4106(gcm(aes))' $KEY_OUT_256 128"
        fi
    else
        fail "Wrong usage, KEY_LEN 128|256"
    fi

    if [[ "$SHOULD_OFFLOAD" == "" || "$SHOULD_OFFLOAD" == "no-offload" ]]; then
        OFFLOAD_IN=""
        OFFLOAD_OUT=""
    elif [ "$SHOULD_OFFLOAD" == "offload" ]; then
        OFFLOAD_IN="offload dev ${nic} dir in"
        OFFLOAD_OUT="offload dev ${nic} dir out"
    elif [ "$SHOULD_OFFLOAD" == "full_offload" ]; then
        OFFLOAD_IN="full_offload dev ${nic} dir in"
        OFFLOAD_OUT="full_offload dev ${nic} dir out"
    else
        fail "Wrong usage, SHOULD_OFFLOAD needs to be set to offload for IPsec crypto offload, full_offload for IPsec full offload, no-offload for SW IPsec"
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

    if [[ ( "$MODE" == "local" || "$MODE" == "local_vf" ) && "$IPSEC_MODE" == "transport" ]]; then
        eval "$cmds"
        ip xfrm state flush
        ip xfrm policy flush
        ip xfrm state add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp spi 1000 reqid 10000 $ALGO_LINE_IN mode $IPSEC_MODE sel src $EFFECTIVE_LIP dst $EFFECTIVE_RIP $OFFLOAD_OUT
        ip xfrm state add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp spi 1001 reqid 10001 $ALGO_LINE_OUT mode $IPSEC_MODE sel src $EFFECTIVE_RIP dst $EFFECTIVE_LIP $OFFLOAD_IN
        ip xfrm policy add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP dir out tmpl src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp reqid 10000 mode $IPSEC_MODE
        ip xfrm policy add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP dir in tmpl src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp reqid 10001 mode $IPSEC_MODE
        ip xfrm policy add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP dir fwd tmpl src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp reqid 10001 mode $IPSEC_MODE
    elif [[ ( "$MODE" == "remote" || "$MODE" == "remote_vf" ) && "$IPSEC_MODE" == "transport" ]]; then
        on_remote "$cmds"
        on_remote "
            ip xfrm state flush
            ip xfrm policy flush
            ip xfrm state add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp spi 1000 reqid 10000 $ALGO_LINE_IN mode $IPSEC_MODE sel src $EFFECTIVE_LIP dst $EFFECTIVE_RIP $OFFLOAD_IN
            ip xfrm state add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp spi 1001 reqid 10001 $ALGO_LINE_OUT mode $IPSEC_MODE sel src $EFFECTIVE_RIP dst $EFFECTIVE_LIP $OFFLOAD_OUT
            ip xfrm policy add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP dir in tmpl src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp reqid 10000 mode $IPSEC_MODE
            ip xfrm policy add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP dir out tmpl src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp reqid 10001 mode $IPSEC_MODE
            ip xfrm policy add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP dir fwd tmpl src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp reqid 10000 mode $IPSEC_MODE"
    elif [[ ( "$MODE" == "local" || "$MODE" == "local_vf" ) && "$IPSEC_MODE" == "tunnel" ]]; then
            eval "$cmds"
            ip xfrm state flush
            ip xfrm policy flush
            ip xfrm state add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp spi 1000 reqid 10000 $ALGO_LINE_IN mode $IPSEC_MODE $OFFLOAD_OUT
            ip xfrm state add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp spi 1001 reqid 10001 $ALGO_LINE_IN mode $IPSEC_MODE $OFFLOAD_IN
            ip xfrm policy add src $EFFECTIVE_LIP dst $EFFECTIVE_RIP dir out tmpl src $EFFECTIVE_LIP dst $EFFECTIVE_RIP proto esp reqid 10000 mode tunnel
            ip xfrm policy add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP dir in tmpl src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp reqid 10001 mode tunnel
            ip xfrm policy add src $EFFECTIVE_RIP dst $EFFECTIVE_LIP dir fwd tmpl src $EFFECTIVE_RIP dst $EFFECTIVE_LIP proto esp reqid 10001 mode tunnel
    elif [[ ( "$MODE" == "remote" || "$MODE" == "remote_vf" ) && "$IPSEC_MODE" == "tunnel" ]]; then
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
    local SHOULD_OFFLOAD=${4:-"no-offload"}
    local TRUSTED_VFS=${5:-"no-trusted"}
    local FUNC_MODE="local"

    if [ $TRUSTED_VFS == "trusted_vfs" ]; then
        FUNC_MODE="local_vf"
    fi

    ipsec_config $FUNC_MODE $IPSEC_MODE $KEY_LEN $IP_PROTO $SHOULD_OFFLOAD
}

function ipsec_config_remote() {
    local IPSEC_MODE="$1"
    local KEY_LEN="$2"
    local IP_PROTO="$3"
    local SHOULD_OFFLOAD=${4:-"no-offload"}
    local TRUSTED_VFS=${5:-"no-trusted"}
    local FUNC_MODE="remote"

    if [ $TRUSTED_VFS == "trusted_vfs" ]; then
        FUNC_MODE="remote_vf"
    fi

    ipsec_config $FUNC_MODE $IPSEC_MODE $KEY_LEN $IP_PROTO $SHOULD_OFFLOAD
}

function ipsec_config_on_both_sides() {
    local IPSEC_MODE="$1"
    local KEY_LEN="$2"
    local IP_PROTO="$3"
    local SHOULD_OFFLOAD=${4:-"no-offload"}
    local TRUSTED_VFS=${5:-"no-trusted"}

    ipsec_config_local $IPSEC_MODE $KEY_LEN $IP_PROTO $SHOULD_OFFLOAD $TRUSTED_VFS
    ipsec_config_remote $IPSEC_MODE $KEY_LEN $IP_PROTO $SHOULD_OFFLOAD $TRUSTED_VFS
}

function ipsec_cleanup_local() {
    local dev=${1:-"$NIC"}
    ip xfrm state flush
    ip xfrm policy flush
    ip address flush $dev
}

function ipsec_cleanup_remote() {
    local dev=${1:-"$NIC"}
    on_remote "ip xfrm state flush
               ip xfrm policy flush
               ip address flush $dev"
}

function ipsec_cleanup_on_both_sides() {
    local dev=${1:-"$NIC"}
    ipsec_cleanup_local $dev
    ipsec_cleanup_remote $dev
}

#This function sets back ipsec devlink mode to none
function ipsec_cleanup_devlink_mode_local() {
    local nic=${1:-"$NIC"}
    if [[ `ipsec_get_mode $nic` != "none" ]]; then
        ipsec_set_mode none $nic
    fi
}

#This function sets back ipsec devlink mode to none
function ipsec_cleanup_devlink_mode_remote() {
    local nic=${1:-"$REMOTE_NIC"}
    on_remote "if [[ `ipsec_get_mode $nic` != "none" ]]; then
                   ipsec_set_mode none $nic
               fi"
}

function ipsec_cleanup_devlink_mode_on_both_sides() {
    local local_dev=${1:-"$NIC"}
    local remote_dev=${2:-"$REMOTE_NIC"}
    ipsec_cleanup_devlink_mode_local $local_dev
    ipsec_cleanup_devlink_mode_remote $remote_dev
}

function change_mtu_on_both_sides() {
    local mtu_val=${1}
    local local_dev=${2:-"$NIC"}
    local remote_dev=${3:-"$REMOTE_NIC"}
    ip link set $local_dev mtu $mtu_val
    on_remote ip link set $remote_dev mtu $mtu_val
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
    local nic=${2:-"$NIC"}
    enable_legacy
    echo $mode > /sys/class/net/$nic/compat/devlink/ipsec_mode || err "Failed to set ipsec mode $mode"
    switch_mode_switchdev
}

function ipsec_set_mode_on_remote() {
    local mode=$1
    local nic=${2:-"$NIC"}
    on_remote_exec "ipsec_set_mode $mode $nic"
}

function ipsec_get_mode() {
    local nic=${1:-"NIC"}
    cat /sys/class/net/$nic/compat/devlink/ipsec_mode
}

function ipsec_set_trusted_vfs(){
    require_mlxreg
    config_sriov
    enable_legacy
    unbind_vfs
    title "Set vf trusted mode"
    set_trusted_vf_mode $NIC
    bind_vfs
    reset_tc $VF
    TRUSTED_VFS="trusted_vfs"
}

function ipsec_set_trusted_vfs_on_remote(){
    on_remote_exec "require_mlxreg
                    config_sriov
                    enable_legacy
                    unbind_vfs
                    title "Set vf trusted mode on remote"
                    set_trusted_vf_mode $REMOTE_NIC
                    bind_vfs
                    reset_tc $VF"
    TRUSTED_VFS="trusted_vfs"
}

function ipsec_cleanup_trusted_vfs(){
    reload_modules
}

function ipsec_cleanup_trusted_vfs_on_remote(){
    on_remote_exec "ipsec_cleanup_trusted_vfs"
}

function ipsec_set_trusted_vfs_on_both_sides(){
    ipsec_set_trusted_vfs
    ipsec_set_trusted_vfs_on_remote
}

function ipsec_cleanup_trusted_vfs_on_both_sides(){
    ipsec_cleanup_trusted_vfs
    ipsec_cleanup_trusted_vfs_on_remote
}
