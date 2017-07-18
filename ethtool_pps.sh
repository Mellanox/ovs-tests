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
 
 
RX1=`ethtool -S $DEV | grep rx_packets_phy | awk '{print $2}'`
TX1=`ethtool -S $DEV | grep tx_packets_phy | awk '{print $2}'`
sleep $DT
RX2=`ethtool -S $DEV | grep rx_packets_phy | awk '{print $2}'`
TX2=`ethtool -S $DEV | grep tx_packets_phy | awk '{print $2}'`
 
DRX=$(((RX2-RX1)/DT))
DTX=$(((TX2-TX1)/DT))
echo DRX=$DRX
echo DTX=$DTX
echo Combined=$(($DRX+$DTX))
