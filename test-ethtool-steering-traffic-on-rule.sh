#!/bin/bash
#
# Verify traffic on ethtool steering rule
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_remote_server

IP=1.1.1.7
REMOTE_IP=1.1.1.8

config_sriov
enable_switchdev
require_interfaces NIC


function cleanup_remote() {
    on_remote "ip a flush dev $REMOTE_NIC
               ip l del dev vxlan1 &>/dev/null"
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
    on_remote "ip a flush dev $REMOTE_NIC
               ip a add $REMOTE_IP/24 dev $REMOTE_NIC
               ip l set dev $REMOTE_NIC up"
}

function run() {
    ifconfig $NIC $IP/24 up
    config_ethtool_steering
    config_remote

    ping -c 1 -w 1 $REMOTE_IP || fail "Ping failed"

    title "send data from remote"
    c1=`ethtool -S $NIC | egrep "rx${act_ch}_bytes" | awk {'print $2'}`
    on_remote sh -c "echo hello | nc -p 6633 -u $IP" || fail "Remote command failed"
    c2=`ethtool -S $NIC | egrep "rx${act_ch}_bytes" | awk {'print $2'}`

    title "verify traffic on channel $act_ch"
    let c1+=10
    if [ $c1 -lt $c2 ]; then
        success
    else
        err
    fi
}


run
test_done
