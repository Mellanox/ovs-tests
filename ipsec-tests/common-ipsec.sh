IPSEC_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
. $IPSEC_DIR/../common.sh
. $IPSEC_DIR/common-ipsec-offload.sh

function require_ip_xfrm() {
    ip xfrm state &>/dev/null || fail "ipsec is not supported"
}

require_cmd xxd
require_ip_xfrm

LIP="172.16.0.1"
RIP="172.16.0.2"
LIP6="2001:192:168:211::64"
RIP6="2001:192:168:211::65"

function ipsec_rand_hex_key() {
    local size=$1
    local key=`dd if=/dev/urandom count=$size bs=1 2>/dev/null | xxd -p -c $size 2>/dev/null`
    [ -z "$key" ] && return
    echo 0x$key
}

# KEYMAT 20 octets = KEY 16ocets, SALT 4octets
# 128 refers to the KEY without the SALT.
KEY_IN_128=`ipsec_rand_hex_key 20`
KEY_OUT_128=`ipsec_rand_hex_key 20`

# KEYMAT 36 octets = KEY 32ocets, SALT 4octets
# 256 refers to the KEY without the SALT.
KEY_IN_256=`ipsec_rand_hex_key 36`
KEY_OUT_256=`ipsec_rand_hex_key 36`

# assume if one key is empty there is a problem with the generation.
if [ -z "$KEY_IN_128" ]; then
    fail "Empty ipsec keys"
fi

# Usage <MODE> <IPSEC_MODE> <KEY_LEN> <IP_PROTO> [offload]
# MODE = local|remote|local_vf|remote_vf
# IPSEC_MODE = transport|tunnel
# KEY_LEN = 128|256
# IP_PROTO = ipv4|ipv6
# SHOULD_OFFLOAD = [no-offload|offload|full_offload] *empty means no-offload.
function ipsec_config() {
    local MODE="$1"
    local IPSEC_MODE="$2"
    local KEY_LEN="$3"
    local IP_PROTO="$4"
    local SHOULD_OFFLOAD="$5"

    log "ipsec_config $@"

    if [[ "$MODE" == "local" ]]; then
        local nic=$NIC
        local IP=$LIP
        local IP6=$LIP6
        local EFFECTIVE_LIP=$LIP
        local EFFECTIVE_RIP=$RIP
        local EFFECTIVE_LIP6=$LIP6
        local EFFECTIVE_RIP6=$RIP6
    elif [[ "$MODE" == "remote" ]]; then #when on remote packet direction is the opposite (what's going out from local is going in on remote)
        local nic=$REMOTE_NIC
        local IP=$RIP
        local IP6=$RIP6
        local EFFECTIVE_LIP=$RIP
        local EFFECTIVE_RIP=$LIP
        local EFFECTIVE_LIP6=$RIP6
        local EFFECTIVE_RIP6=$LIP6
    elif [[ "$MODE" == "local_vf" ]]; then
        local nic=$VF
        local IP=$LIP
        local IP6=$LIP6
        local EFFECTIVE_LIP=$LIP
        local EFFECTIVE_RIP=$RIP
        local EFFECTIVE_LIP6=$LIP6
        local EFFECTIVE_RIP6=$RIP6
    elif [[ "$MODE" == "remote_vf" ]]; then
        local nic=$VF
        local IP=$RIP
        local IP6=$RIP6
        local EFFECTIVE_LIP=$RIP
        local EFFECTIVE_RIP=$LIP
        local EFFECTIVE_LIP6=$RIP6
        local EFFECTIVE_RIP6=$LIP6
    else
        fail "Wrong usage, MODE local|remote|local_vf|remote_vf"
    fi

    if [[ "$IPSEC_MODE" != "transport" && "$IPSEC_MODE" != "tunnel" ]]; then
        fail "Wrong usage, IPSEC_MODE transport|tunnel"
    fi

    if [[ "$IP_PROTO" != "ipv4" && "$IP_PROTO" != "ipv6" ]]; then
        fail "Wrong usage, IP_PROTO ipv4|ipv6"
    fi

    eval key_in="\$KEY_IN_$KEY_LEN"
    eval key_out="\$KEY_OUT_$KEY_LEN"
    if [ -z "$key_in" ]; then
        fail "Wrong usage, KEY_LEN 128|256"
    fi
    local ALGO_LINE_IN="aead 'rfc4106(gcm(aes))' $key_in 128"
    local ALGO_LINE_OUT="aead 'rfc4106(gcm(aes))' $key_out 128"

    local ofed_sysfs=`ipsec_mode_ofed $nic`
    local offload=$SHOULD_OFFLOAD
    if [ "$offload" == "full_offload" ] && [ -f "$ofed_sysfs" ]; then
        offload="mlnx_ofed_full_offload"
    fi

    if [[ "$offload" == "" || "$offload" == "no-offload" ]]; then
        OFFLOAD_IN=""
        OFFLOAD_OUT=""
    elif [ "$offload" == "offload" ] || [ "$offload" == "full_offload" ]; then
        OFFLOAD_IN="offload dev ${nic} dir in"
        OFFLOAD_OUT="offload dev ${nic} dir out"
    elif [ "$offload" == "mlnx_ofed_full_offload" ]; then
        OFFLOAD_IN="full_offload dev ${nic} dir in"
        OFFLOAD_OUT="full_offload dev ${nic} dir out"
    else
        fail "Wrong usage, SHOULD_OFFLOAD needs to be set to offload for IPsec crypto offload, full_offload for IPsec full offload, no-offload for SW IPsec"
    fi

    if [ "$offload" == "full_offload" ]; then
        fail "upstream ipsec full offload not supported yet"
    fi

    cmds="ip address flush $nic"

    if [[ "$IP_PROTO" == "ipv6" ]]; then
        EFFECTIVE_LIP=$EFFECTIVE_LIP6
        EFFECTIVE_RIP=$EFFECTIVE_RIP6
        cmds="$cmds
              ip -6 address add ${IP6}/112 dev $nic"
    else
        cmds="$cmds
              ip -4 address add ${IP}/16 dev $nic"
    fi

    cmds="$cmds
          ip link set $nic up
          ip xfrm state flush
          ip xfrm policy flush"

    local src_ip=$EFFECTIVE_LIP
    local dst_ip=$EFFECTIVE_RIP
    local reqid_out=10000
    local reqid_in=10001
    local spi_out=1000
    local spi_in=1001
    if [[ ( "$MODE" == "remote" || "$MODE" == "remote_vf" ) ]]; then
        local spi_out=1001
        local spi_in=1000
    fi
    local run_on_remote

    if [[ ( "$MODE" == "local" || "$MODE" == "local_vf" ) && "$IPSEC_MODE" == "transport" ]]; then
        cmds="$cmds
              ip xfrm state add src $src_ip dst $dst_ip proto esp spi $spi_out reqid $reqid_out $ALGO_LINE_IN mode $IPSEC_MODE sel src $src_ip dst $dst_ip $OFFLOAD_OUT &&
              ip xfrm state add src $dst_ip dst $src_ip proto esp spi $spi_in reqid $reqid_in $ALGO_LINE_OUT mode $IPSEC_MODE sel src $dst_ip dst $src_ip $OFFLOAD_IN &&
              ip xfrm policy add src $src_ip dst $dst_ip dir out tmpl src $src_ip dst $dst_ip proto esp reqid $reqid_out mode $IPSEC_MODE &&
              ip xfrm policy add src $dst_ip dst $src_ip dir in tmpl src $dst_ip dst $src_ip proto esp reqid $reqid_in mode $IPSEC_MODE &&
              ip xfrm policy add src $dst_ip dst $src_ip dir fwd tmpl src $dst_ip dst $src_ip proto esp reqid $reqid_in mode $IPSEC_MODE"
    elif [[ ( "$MODE" == "remote" || "$MODE" == "remote_vf" ) && "$IPSEC_MODE" == "transport" ]]; then
        run_on_remote=1
        cmds="$cmds
              ip xfrm state add src $src_ip dst $dst_ip proto esp spi $spi_out reqid $reqid_out $ALGO_LINE_OUT mode $IPSEC_MODE sel src $src_ip dst $dst_ip $OFFLOAD_OUT &&
              ip xfrm state add src $dst_ip dst $src_ip proto esp spi $spi_in reqid $reqid_in $ALGO_LINE_IN mode $IPSEC_MODE sel src $dst_ip dst $src_ip $OFFLOAD_IN &&
              ip xfrm policy add src $src_ip dst $dst_ip dir out tmpl src $src_ip dst $dst_ip proto esp reqid $reqid_out mode $IPSEC_MODE &&
              ip xfrm policy add src $dst_ip dst $src_ip dir in tmpl src $dst_ip dst $src_ip proto esp reqid $reqid_in mode $IPSEC_MODE &&
              ip xfrm policy add src $dst_ip dst $src_ip dir fwd tmpl src $dst_ip dst $src_ip proto esp reqid $reqid_in mode $IPSEC_MODE"
    elif [[ ( "$MODE" == "local" || "$MODE" == "local_vf" ) && "$IPSEC_MODE" == "tunnel" ]]; then
        cmds="$cmds
              ip xfrm state add src $src_ip dst $dst_ip proto esp spi $spi_out reqid $reqid_out $ALGO_LINE_IN mode $IPSEC_MODE $OFFLOAD_OUT &&
              ip xfrm state add src $dst_ip dst $src_ip proto esp spi $spi_in reqid $reqid_in $ALGO_LINE_IN mode $IPSEC_MODE $OFFLOAD_IN &&
              ip xfrm policy add src $src_ip dst $dst_ip dir out tmpl src $src_ip dst $dst_ip proto esp reqid $reqid_out mode tunnel &&
              ip xfrm policy add src $dst_ip dst $src_ip dir in  tmpl src $dst_ip dst $src_ip proto esp reqid $reqid_in mode tunnel &&
              ip xfrm policy add src $dst_ip dst $src_ip dir fwd tmpl src $dst_ip dst $src_ip proto esp reqid $reqid_in mode tunnel"
    elif [[ ( "$MODE" == "remote" || "$MODE" == "remote_vf" ) && "$IPSEC_MODE" == "tunnel" ]]; then
        run_on_remote=1
        cmds="$cmds
              ip xfrm state add src $src_ip dst $dst_ip proto esp spi $spi_out reqid $reqid_out $ALGO_LINE_IN mode $IPSEC_MODE $OFFLOAD_OUT &&
              ip xfrm state add src $dst_ip dst $src_ip proto esp spi $spi_in reqid $reqid_in $ALGO_LINE_IN mode $IPSEC_MODE $OFFLOAD_IN &&
              ip xfrm policy add src $src_ip dst $dst_ip dir out tmpl src $src_ip dst $dst_ip proto esp reqid $reqid_out mode tunnel &&
              ip xfrm policy add src $dst_ip dst $src_ip dir in  tmpl src $dst_ip dst $src_ip proto esp reqid $reqid_in mode tunnel &&
              ip xfrm policy add src $dst_ip dst $src_ip dir fwd tmpl src $dst_ip dst $src_ip proto esp reqid $reqid_in mode tunnel"
    else
        fail "Cannot config ipsec mode $MODE ipsec_mode $IPSEC_MODE"
    fi

    if [ "$run_on_remote" == "1" ]; then
        on_remote "$cmds" || fail "Failed to config ipsec"
    else
        eval "$cmds" || fail "Failed to config ipsec"
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

function ipsec_flush_local() {
    local dev=${1:-"$NIC"}
    ip xfrm state flush
    ip xfrm policy flush
    ip address flush $dev
}

function ipsec_flush_remote() {
    local dev=${1:-"$NIC"}
    on_remote "ip xfrm state flush
               ip xfrm policy flush
               ip address flush $dev"
}

function ipsec_cleanup_on_both_sides() {
    local dev=${1:-"$NIC"}
    ipsec_flush_local $dev
    ipsec_flush_remote $dev
}

function ipsec_clear_mode_on_both_sides() {
    local local_dev=${1:-"$NIC"}
    local remote_dev=${2:-"$REMOTE_NIC"}
    ipsec_set_mode none $local_dev
    ipsec_set_mode_on_remote none $remote_dev
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


function ipsec_mode_ofed() {
    local nic=$1
    echo "/sys/class/net/$nic/compat/devlink/ipsec_mode"
}

function ipsec_set_mode() {
    local mode=$1
    local nic=${2:-"$NIC"}
    # this old mlnx ofed compat
    local sysfs=`ipsec_mode_ofed $nic`
    [ ! -f $sysfs ] && return
    local old=`cat $sysfs`
    [ "$old" == "$mode" ] && return
    enable_legacy
    echo $mode > $sysfs || err "Failed to set ipsec mode $mode"
    switch_mode_switchdev
}

function ipsec_set_mode_on_remote() {
    local mode=$1
    local nic=${2:-"$NIC"}
    on_remote_exec "ipsec_set_mode $mode $nic"
}

function ipsec_set_trusted_vfs() {
    require_mlxreg
    config_sriov
    enable_legacy
    unbind_vfs
    title "Set vf trusted mode"
    set_trusted_vf_mode $NIC
    bind_vfs
    reset_tc $VF
    fail_if_err
    TRUSTED_VFS="trusted_vfs"
}

function ipsec_set_trusted_vfs_on_remote() {
    on_remote_exec ipsec_set_trusted_vfs || fail "Remove config trusted_vfs failed"
    TRUSTED_VFS="trusted_vfs"
}

function ipsec_cleanup_trusted_vfs() {
    reload_modules
}

function ipsec_cleanup_trusted_vfs_on_remote() {
    on_remote_exec "ipsec_cleanup_trusted_vfs"
}

function ipsec_set_trusted_vfs_on_both_sides() {
    ipsec_set_trusted_vfs
    ipsec_set_trusted_vfs_on_remote
}

function ipsec_cleanup_trusted_vfs_on_both_sides() {
    ipsec_cleanup_trusted_vfs
    ipsec_cleanup_trusted_vfs_on_remote
}
