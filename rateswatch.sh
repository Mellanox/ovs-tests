#!/bin/bash

devs=${@:?Which devices?}

function get_rx_bytes() {
    ethtool -S $1 | grep -E 'rx_bytes_phy|vport_rx_bytes' | awk {'print $2'}
}

function get_tx_bytes() {
    ethtool -S $1 | grep -E 'tx_bytes_phy|vport_tx_bytes' | awk {'print $2'}
}

function get_rx_pkts() {
    ethtool -S $1 | grep -E 'rx_packets_phy|vport_rx_packets' | awk {'print $2'}
}

function get_tx_pkts() {
    ethtool -S $1 | grep -E 'tx_packets_phy|vport_tx_packets' | awk {'print $2'}
}

function humanrate() {
    local rate=$1

    (( rate > 1000*1000*1000 )) && echo "$(bc <<< "scale=3; $rate/(1000*1000*1000)") G" && return
    (( rate > 1000*1000 )) && echo "$(bc <<< "scale=3; $rate/(1000*1000)") M" && return
    (( rate > 1000 )) && echo "$(bc <<< "scale=3; $rate/1000") K" && return
    echo "$(bc <<< "scale=3; $rate/1000") K"
}

function rateswatch() {
    local devs=$@

    while true; do
        for d in $devs; do
            declare ${d}_b_tx=`get_tx_bytes $d`
            declare ${d}_b_rx=`get_rx_bytes $d`
            declare ${d}_b_ptx=`get_tx_pkts $d`
            declare ${d}_b_prx=`get_rx_pkts $d`
        done
        sleep 1
        for d in $devs; do
            a_tx=`get_tx_bytes $d`
            a_rx=`get_rx_bytes $d`
            a_ptx=`get_tx_pkts $d`
            a_prx=`get_rx_pkts $d`
            b_tx=${d}_b_tx
            b_rx=${d}_b_rx
            b_ptx=${d}_b_ptx
            b_prx=${d}_b_prx
            echo -en "                                                                                                   \r";
            echo -en " dev: $d "
            echo -en "\ttx: `humanrate $((($a_tx - ${!b_tx})*8))`ibs "
            echo -en "\t(`humanrate $(($a_ptx - ${!b_ptx}))`pps)"
            echo -en "\trx: `humanrate $((($a_rx - ${!b_rx})*8))`ibs "
            echo -en "\t(`humanrate $(($a_prx - ${!b_prx}))`pps)"
            echo ""
        done
        for d in $devs; do
            echo -en "\033[1A\r";
        done
    done
}


rateswatch $devs
