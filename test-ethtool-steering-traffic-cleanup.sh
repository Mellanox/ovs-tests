#!/bin/bash
#
# Verify ethtool steering rules are deleted after moving back to NIC mode
#
# Bug SW #2234613: [ASAP] stale ethtool steering rules remain after moving back to legacy mode
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

REMOTE_SERVER=${REMOTE_SERVER:-$1}
REMOTE_NIC=${REMOTE_NIC:-$2}

require_remote_server

IP=1.1.1.7
REMOTE_IP=1.1.1.8

config_sriov
enable_switchdev
require_interfaces NIC


function cleanup_remote() {
    sleep 1
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev vxlan1 &>/dev/null
}

function cleanup() {
    ip a flush dev $NIC
    ethtool -U $NIC delete 1 &>/dev/null
    ethtool -X $NIC equal 1
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config_ethtool_steering() {
    local max_ch=$(ethtool -l $NIC | grep Combined | head -1 | cut -f2-)
    local max_eq
    let max_eq=max_ch-2
    let act_ch=max_ch-1

    echo "max_ch $max_ch max_eq $max_eq act_ch $act_ch"
    ethtool -L $NIC combined $max_ch
    ethtool -X $NIC equal $max_eq
    ethtool -U $NIC flow-type udp4 src-port 6633 action $act_ch loc 1
    ethtool -u $NIC
}

function config_remote() {
    on_remote ip a flush dev $REMOTE_NIC || fail "Cannot config remote nic $REMOTE_NIC"
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip l set dev $REMOTE_NIC up
}

function run() {
    title "Config ethtool steering"
    config_ethtool_steering

    title "Disable sriov"
    disable_sriov
    config_remote

    ifconfig $NIC $IP/24 up
    sleep 1

    ping -c 1 -w 1 $REMOTE_IP || fail "Ping failed"

    title "send data from remote"
    c1=`ethtool -S $NIC | grep "rx_bytes:" | awk {'print $2'}`
    on_remote sh -c "echo hello | nc -p 6633 -u $IP" || fail "Remote command failed"
    c2=`ethtool -S $NIC | grep "rx_bytes:" | awk {'print $2'}`

    title "verify traffic received on uplink"
    let c1+=10
    if [ $c1 -lt $c2 ]; then
        success
    else
        err "rx bytes didn't increase"
    fi

    config_sriov
}


run
test_done
