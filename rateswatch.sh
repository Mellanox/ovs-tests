#!/bin/bash

devs=${@:?Which devices?}

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
            declare ${d}_b_tx=`ethtool -S $d | grep "tx_bytes_phy:" | awk '{ print $2 }'`
            declare ${d}_b_rx=`ethtool -S $d | grep "rx_bytes_phy:" | awk '{ print $2 }'`
            declare ${d}_b_ptx=`ethtool -S $d | grep "tx_packets_phy:" | awk '{ print $2 }'`
            declare ${d}_b_prx=`ethtool -S $d | grep "rx_packets_phy:" | awk '{ print $2 }'`
        done
        sleep 1
        for d in $devs; do
            a_tx=`ethtool -S $d | grep "tx_bytes_phy:" | awk '{ print $2 }'`
            a_rx=`ethtool -S $d | grep "rx_bytes_phy:" | awk '{ print $2 }'`
            a_ptx=`ethtool -S $d | grep "tx_packets_phy:" | awk '{ print $2 }'`
            a_prx=`ethtool -S $d | grep "rx_packets_phy:" | awk '{ print $2 }'`
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
