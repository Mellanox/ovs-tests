#!/bin/bash

num=${1:?num}
SKIP=${2:-skip_sw}
ETH=${3:-ens5f0}
TC=tc

echo "SKIP $SKIP ETH $ETH"

## just to be sure, delete all existing rules $TC qdisc del dev ${ETH} ingress

#ethtool -K ${ETH} hw-tc-offload on

#$TC qdisc add dev ${ETH} ingress

OUT="/tmp/tc_add_batch_$num"

rm -fr $OUT

count=0

for ((i = 0; i < 99; i++)); do
    for ((j = 0; j < 99; j++)); do
        for ((m = 0; m < 99; m++)); do
            #NUM1=`printf "%02x" $i`
            #NUM2=`printf "%02x" $j`
            #NUM3=`printf "%02x" $m`
            #SMAC="e4:11:22:$NUM1:$NUM2:$NUM3"
            #DMAC="e4:11:33:$NUM1:$NUM2:$NUM3"
            SMAC="e4:11:22:$i:$j:$m"
            DMAC="e4:11:33:$i:$j:$m"
            echo "filter add dev ${ETH} prio 1 protocol ip parent ffff: \
                flower \
                $SKIP \
                src_mac $SMAC \
                dst_mac $DMAC \
                action drop"
            ((count+=1))
            let p=count%1000
            if [ $p == 0 ]; then
                echo -n " $count" > /dev/stderr
            fi
            if ((count>=num)); then
                echo > /dev/stderr
                exit
            fi
        done
    done
done > $OUT
echo > /dev/stderr

#$TC -b /tmp/tc_add_batch_$num
