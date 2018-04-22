#!/bin/bash

Usage() {
	echo
	echo "usage: $0 DEV1 [ DEV2 ] to examine [ delta T ]"
	echo
	exit 1
}

if [ A$1 = A  ] ; then
	Usage
fi

if [ $1 = "-h" ] ; then
        Usage
fi

DEV1=$1
DEV2=$2

read_ethx_val() {
	DEV=$1
	tok=$2
	ethtool -S $DEV | grep $tok | awk '{print $2}'
}

human_bytes() {
	N=$1
	N=$((N*8))
	if [ $N -gt 1000000000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1024*1024*1024)") Gbps"
		return
	fi
	if [ $N -gt 1000000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1024*1024)") Mbps"
		return
	fi
	if [ $N -gt 1000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1024)") Kbps"
		return
	fi
	echo "$N bps"
}

human_pps() {
	N=$1
	if [ $N -gt 1000000000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1000*1000*1000)") GPPS"
		return
	fi
	if [ $N -gt 1000000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1000*1000)") MPPS"
		return
	fi
	if [ $N -gt 1000 ] ; then
		echo "$(bc<<<"scale=2; $N/(1000)") KPPS"
		return
	fi
	echo "$N PPS"

}



DT=${3:-1}
echo DT=$DT

clear
echo 
echo
printf "%10s %-30s %-30s\n" " " "TX" "RX"

while [ 1 ] ; do
    RX1D1=`read_ethx_val $DEV1 rx_bytes_phy`
    TX1D1=`read_ethx_val $DEV1 tx_bytes_phy`
    PRX1D1=`read_ethx_val $DEV1 rx_packets_phy`
    PTX1D1=`read_ethx_val $DEV1 tx_packets_phy`
    if [ $DEV2 ] ; then
            RX1D2=`read_ethx_val $DEV2 rx_bytes_phy`
            TX1D2=`read_ethx_val $DEV2 tx_bytes_phy`
            PRX1D2=`read_ethx_val $DEV2 rx_packets_phy`
            PTX1D2=`read_ethx_val $DEV2 tx_packets_phy`
    fi
    sleep $DT
    RX2D1=`read_ethx_val $DEV1 rx_bytes_phy`
    TX2D1=`read_ethx_val $DEV1 tx_bytes_phy`
    PRX2D1=`read_ethx_val $DEV1 rx_packets_phy`
    PTX2D1=`read_ethx_val $DEV1 tx_packets_phy`
    if [ $DEV2 ] ; then
            RX2D2=`read_ethx_val $DEV2 rx_bytes_phy`
            TX2D2=`read_ethx_val $DEV2 tx_bytes_phy`
            PRX2D2=`read_ethx_val $DEV2 rx_packets_phy`
            PTX2D2=`read_ethx_val $DEV2 tx_packets_phy`
    fi

    DRXD1=`human_bytes $(((RX2D1-RX1D1)/DT))`
    DTXD1=`human_bytes $(((TX2D1-TX1D1)/DT))`
    PDRXD1=`human_pps $(((PRX2D1-PRX1D1)/DT))`
    PDTXD1=`human_pps $(((PTX2D1-PTX1D1)/DT))`

    printf   "%-10s %-30s %-30s\n"  "$DEV1" "$DTXD1 [$PDTXD1]" "$DRXD1 [$PDRXD1]"
    if [ $DEV2 ] ; then
            DRXD2=`human_bytes $(((RX2D2-RX1D2)/DT))`
            DTXD2=`human_bytes $(((TX2D2-TX1D2)/DT))`
            PDRXD2=`human_pps $(((PRX2D2-PRX1D2)/DT))`
            PDTXD2=`human_pps $(((PTX2D2-PTX1D2)/DT))`
            printf   "%-10s %-30s %-30s\n"  "$DEV2" "$DTXD2 [$PDTXD2]" "$DRXD2 [$PDRXD2]"
            echo -e "\033[3A"
    else
            echo -e "\033[2A"
    fi
done

