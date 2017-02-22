#!/bin/bash

START_PORT=${1:-1}
END_PORT=${2:-10000}
SKIP=${3:-2}
NUM_MACS=${4:-1}
BRIDGE=${5:-t_br0}

date
echo "Droping $START_PORT to $END_PORT (with skip: $SKIP), on $NUM_MACS macs"
echo "Usage: $0 [Start port] [End port] [Skip] [Num of macs to set]"

MACS=($(ip link show | grep vf | cut -d " " -f 8 | cut -d "," -f 1))
echo ${MACS[@]}
#for (( i=0; i<${#MACS[@]}; i++ )); do echo ${MACS[i]}; done


i=0
P=$START_PORT
while [  $P -lt $END_PORT ]; do
	
	#for (( i=0; i<${#MACS[@]} && i<$NUM_MACS; i++ )); do ovs-ofctl add-flow $BRIDGE dl_dst=${MACS[i]},dl_type=0x0800,nw_proto=0x11,udp_src=$P,actions=drop; done
	#ovs-ofctl add-flow $BRIDGE dl_dst=${MACS[i]},dl_type=0x0800,nw_proto=0x11,udp_src=$P,actions=drop
	ovs-ofctl add-flow $BRIDGE dl_type=0x0800,nw_proto=0x11,udp_src=$P,actions=drop
	#for (( i=0; i<${#MACS[@]} && i<$NUM_MACS; i++ )); do ovs-ofctl add-flow $BRIDGE dl_dst=${MACS[i]},dl_type=0x0800,nw_proto=0x1,actions=drop; done

    	let P=P+$SKIP
	let PROGRESS=(P*100/END_PORT)
	echo -ne "$PROGRESS%   \r"
done
echo -ne '\n'

ovs-ofctl dump-flows $BRIDGE | head
ovs-ofctl dump-flows $BRIDGE | wc -l

ovs-dpctl dump-flows hw_netlink@ovs-hw_netlink

exit
