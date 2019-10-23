#!/bin/bash
 
DEV=$1
 
if [ "$1" = "" ] || [ "$1" = "-h" ] ; then
    echo "Usage: `basename $0` dev [dt]"
    echo " dev - uplink device"
    echo " dt  - delta time"
    exit 1
fi
 
DT=${2:-3}
echo DT=$DT

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

RX1=`get_rx_pkts $DEV`
TX1=`get_tx_pkts $DEV`
sleep $DT
RX2=`get_rx_pkts $DEV`
TX2=`get_tx_pkts $DEV`
 
DRX=$(((RX2-RX1)/DT))
DTX=$(((TX2-TX1)/DT))
echo DRX=$DRX
echo DTX=$DTX
echo Combined=$(($DRX+$DTX))
