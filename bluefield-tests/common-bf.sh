BF_DIR=$(cd "$(dirname ${BASH_SOURCE[0]})" &>/dev/null && pwd)

. $BF_DIR/../common.sh

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
}

function require_remote_bf() {
    if [ -z "$REMOTE_BF_IP" ]; then
        fail "Remote BF IP is not configured"
    fi

    log "Remote BF $REMOTE_BF_IP"
    on_remote_bf true || fail "Remote BF command failed"
}

function config_vf_ns() {
    local ns=$1
    local vf=$2
    local ip=$3  # optional
    local mac=$4 # optional
    local prefix=24

    if [[ "$ip" == *":"* ]]; then
        # ipv6
        prefix=64
    fi

    echo "[$ns] $vf (${mac:+$mac/}$ip)"
    ip netns add $ns
    ${mac:+ip link set $vf address $mac}
    ip link set $vf netns $ns
    ${ip:+ip -netns $ns address replace dev $vf $ip/$prefix}
    ip -netns $ns link set $vf up
}
