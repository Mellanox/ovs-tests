#!/bin/bash
#
# Verify traffic spread on multiple channels that were set but not others.
#
# Require external server
#
# IGNORE_FROM_TEST_ALL

my_dir="$(dirname "$0")"
. $my_dir/common.sh

REMOTE_SERVER=${1:?Require remote server}
REMOTE_NIC=${2:-ens1f0}

require_remote_server

IP=1.1.1.7
REMOTE_IP=1.1.1.8

config_sriov
enable_switchdev_if_no_rep $REP
require_interfaces NIC


function cleanup_remote() {
    on_remote ip a flush dev $REMOTE_NIC
    on_remote ip l del dev vxlan1 &>/dev/null
}

function cleanup() {
    ip a flush dev $NIC
    ethtool -X $NIC equal 1
    cleanup_remote
    sleep 0.5
}
trap cleanup EXIT

function config_ethtool_steering() {
    max_ch=$(ethtool -l $NIC | grep Combined | head -1 | cut -f2-)
    let last_ch=max_ch-1

    ethtool -L $NIC combined $max_ch
    ethtool -X $NIC equal 2
    ethtool -x $NIC
    ethtool -u $NIC
}

function config_remote() {
    on_remote ip a flush dev $REMOTE_NIC || fail "Cannot config remote nic $REMOTE_NIC"
    on_remote ip a add $REMOTE_IP/24 dev $REMOTE_NIC
    on_remote ip l set dev $REMOTE_NIC up
}

function get_rq_packets() {
    rqs=()
    for i in `seq 0 $last_ch`; do
        rqs+=(`ethtool -S $NIC | egrep "rx${i}_bytes" | awk {'print $2'}`)
    done
}

function run() {
    ifconfig $NIC $IP/24 up
    config_ethtool_steering
    config_remote

    ping -c 1 -w 1 $REMOTE_IP || fail "Ping failed"

    title "send data from remote"
    get_rq_packets
    sport=6633
    for i in `seq 20`; do
        on_remote sh -c "echo thisisasimpledatatransferyoudonotreallyneedtochangethis | nc -p $sport -u $IP" || fail "Remote command failed"
        let sport+=1
    done
    rqs_old=(${rqs[@]})
    get_rq_packets

    title "verify counters on all channels"
    for i in `seq 0 $last_ch`; do
        if [ $i -lt 2 ]; then
            if [ ${rqs_old[$i]} != ${rqs[$i]} ]; then
                echo "diff on channel $i - ok"
            else
                err "Expected diff on channel $i"
            fi
        else # $i >= 2
            if [ ${rqs_old[$i]} != ${rqs[$i]} ]; then
                err "Expected no diff on channel $i"
            fi
        fi
    done
}


run
test_done
