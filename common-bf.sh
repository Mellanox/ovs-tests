function on_bf() {
    __on_remote $BF_IP "$@"
}

function on_remote_bf() {
    __on_remote $REMOTE_BF_IP "$@"
}

function on_bf_exec() {
    __on_remote_exec $BF_IP "$@"
}

function on_remote_bf_exec() {
    __on_remote_exec $REMOTE_BF_IP "$@"
}

function require_bf() {
    if [ -z "$BF_IP" ]; then
        fail "BF IP is not configured"
    fi

    log "BF $BF_IP"
    on_bf true || fail "BF command failed"
    print_remote_test_separator $BF_IP
    on_bf "echo MLNX_OFED \`modinfo --field version mlx5_core\` | tee -a /dev/kmsg"
}

function require_remote_bf() {
    if [ -z "$REMOTE_BF_IP" ]; then
        fail "Remote BF IP is not configured"
    fi

    log "Remote BF $REMOTE_BF_IP"
    on_remote_bf true || fail "Remote BF command failed"
}

function __config_vf() {
    local ns=$1
    local vf=$2
    local ip=$3  # optional
    local mac=$4 # optional
    local prefix=24

    if [[ "$ip" == *":"* ]]; then
        # ipv6
        prefix=64
    fi

    ip netns add $ns
    ${mac:+ip link set $vf address $mac}
    ip link set $vf netns $ns
    ${ip:+ip -netns $ns address replace dev $vf $ip/$prefix}
    ip -netns $ns link set $vf up
}

function __config_rep() {
    local rep=$1

    ip address flush dev $rep
    ip link set dev $rep up
}

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4  # optional
    local mac=$5 # optional

    echo "[$ns] $vf (${mac:+$mac/}$ip) -> BF $rep"
    __config_vf $ns $vf $ip $mac
    on_bf_exec "__config_rep $rep"
}

function config_remote_bf_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4  # optional
    local mac=$5 # optional

    echo "[$ns] $vf (${mac:+$mac/}$ip) -> BF $rep"
    on_remote_exec "__config_vf $ns $vf $ip $mac"
    on_remote_bf_exec "__config_rep $rep"
}
