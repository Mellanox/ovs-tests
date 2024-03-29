IPSEC_LIBRESWAN_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)
. $IPSEC_LIBRESWAN_DIR/common-ipsec.sh

IPSEC_CONFIG_DIR="/etc/ipsec.d"
IPSEC_CONN="mytunnel"
IPSEC_MYTUNNEL_CONF="$IPSEC_CONFIG_DIR/${IPSEC_CONN}.conf"
IPSEC_TMP_CONF="/tmp/${IPSEC_CONN}.conf"

function require_ipsec() {
    require_cmd ipsec
    ipsec --version | grep Libreswan || fail "ipsec is not Libreswan"
}

require_ipsec

function ipsec_dump_hostkeys() {
    ipsec showhostkey --dump | grep -o "RSA keyid: [^ ]*" | awk {'print $3'}
}

# get the first rsa key
function ipsec_get_hostkey() {
    ipsec_dump_hostkeys | head -1
}

function __ipsec_init_keys() {
    local dump=`ipsec showhostkey --dump 2>/dev/null`
    if [ $? == 1 ] || [ -z "$dump" ]; then
        ipsec initnss
        ipsec newhostkey
    fi
}

function ipsec_get_left_key() {
    local rsaid=$1
    ipsec showhostkey --left --rsaid $rsaid
}

#note: runs on remote
function ipsec_get_right_key() {
    local rsaid=$1
    on_remote ipsec showhostkey --right --rsaid $rsaid
}

function ipsec_setup_start() {
    log "Start ipsec service"
    ipsec setup start
    on_remote ipsec setup start
}

function ipsec_setup_stop() {
    log "Stop ipsec service"
    ipsec setup stop
    on_remote ipsec setup stop
}

function ipsec_trafficstatus() {
    local conn=$1
    [ -z "$conn" ] && ipsec trafficstatus
    [ -n "$conn" ] && ipsec trafficstatus | grep -w $conn
}

function ipsec_config_conn() {
    local local_offload_mode=${1:-"no-offload"}
    local remote_offload_mode=${2:-"no-offload"}
    __ipsec_init_keys
    local key=`ipsec_get_hostkey`

    on_remote_exec __ipsec_init_keys
    local remote_key=`on_remote_exec ipsec_get_hostkey`

    if [ -z "$key" ]; then
        fail "Missing ipsec local host key"
    fi

    if [ -z "$remote_key" ]; then
        fail "Missing ipsec remote host key"
    fi

    echo "key: $key"
    echo "remote key: $remote_key"

    log "Create ipsec config"
    ipsec_create_conf $local_offload_mode $remote_offload_mode
    log "Copy ipsec config to remote"
    scp2 $IPSEC_TMP_CONF $REMOTE_SERVER:$IPSEC_MYTUNNEL_CONF
}

function ipsec_create_conf() {
    local local_offload="$1"
    local remote_offload="$2"
    local nic_offload="no"
    local leftsig=`ipsec_get_left_key $key`
    local rightsig=`ipsec_get_right_key $remote_key`

    echo "left sig: $leftsig"
    echo "right sig: $rightsig"

    [ -z "$leftsig" ] && fail "Missing ipsec left sig"
    [ -z "$rightsig" ] && fail "Missing ipsec right sig"

    if [ "$local_offload" == "crypto" ]; then
        nic_offload="yes"
    elif [ "$local_offload" == "packet" ]; then
        nic_offload="packet"
    fi

    echo "
conn $IPSEC_CONN
    leftid=@west
    left=$LIP
    $leftsig
    rightid=@east
    right=$RIP
    $rightsig
    authby=rsasig
    auto=ondemand
    type=transport
    nic-offload=$nic_offload" > $IPSEC_MYTUNNEL_CONF

    nic_offload="no"
    if [ "$remote_offload" == "crypto" ]; then
        nic_offload="yes"
    elif [ "$remote_offload" == "packet" ]; then
        nic_offload="packet"
    fi
    echo "

conn $IPSEC_CONN
    leftid=@west
    left=$LIP
    $leftsig
    rightid=@east
    right=$RIP
    $rightsig
    authby=rsasig
    auto=ondemand
    type=transport
    nic-offload=$nic_offload" > $IPSEC_TMP_CONF

}

function ipsec_config_setup() {
    local local_offload_mode=${1:-"no-offload"}
    local remote_offload_mode=${2:-"no-offload"}
    ipsec_setup_stop
    ip a r dev $NIC $LIP/24
    ip l s dev $NIC up
    on_remote "ip a r dev $NIC $RIP/24
               ip l s dev $NIC up"
    ipsec_config_conn $local_offload_mode $remote_offload_mode
    ipsec_setup_start
    ipsec auto --add $IPSEC_CONN || fail "Failed to add ipsec tunnel"
    ipsec auto --start $IPSEC_CONN || fail "Failed to start ipsec tunnel"
}

function ipsec_clear_setup() {
    ipsec auto --down $IPSEC_CONN
    ipsec auto --delete $IPSEC_CONN
    ipsec_setup_stop
}

function ipsec_verify_trafficstatus() {
    local in=`ipsec_trafficstatus $IPSEC_CONN | grep -o "inBytes=[0-9]\+" | cut -d= -f2`
    local out=`ipsec_trafficstatus $IPSEC_CONN | grep -o "outBytes=[0-9]\+" | cut -d= -f2`

    if [ -z "$in" ] || [ "$in" == 0 ]; then
        err "Mssing inBytes"
    fi

    if [ -z "$out" ] || [ "$out" == 0 ]; then
        err "Mssing outBytes"
    fi
}
