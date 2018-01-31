#!/bin/bash

num=${1:?num}
SKIP=${2:-skip_sw}
ETH=${3:-p2p1}
set_index=${4:-0}	# if set_index == 1, all filters share the same action
set_prio=${5:-0}	# if set_prio == 1, all filters will have different prio

echo "SKIP $SKIP ETH $ETH NUM $num INDEX $set_index PRIO $set_prio"

echo "Clean tc rules"
TC=tc
$TC qdisc del dev $ETH ingress > /dev/null 2>&1

tmpdir="/tmp/tc_batch"
rm -fr $tmpdir
mkdir -p $tmpdir

if [[ "$SKIP" == "skip_sw" ]]; then
	OUT="$tmpdir/hw_batch"
fi
if [[ "$SKIP" == "skip_hw" ]]; then
	OUT="$tmpdir/sw_batch"
fi

n=0
count=0
prio=1

if (( set_index == 1 )); then
	index_str="index 1"
else
	index_str=""
fi

echo "Generating batches"

for ((i = 0; i < 99; i++)); do
	for ((j = 0; j < 99; j++)); do
		for ((k = 0; k < 99; k++)); do
			for ((l = 0; l < 99; l++)); do
				SMAC="e4:11:$i:$j:$k:$l"
				DMAC="e4:12:$i:$j:$k:$l"
				echo "filter add dev ${ETH} prio $prio \
protocol ip \
parent ffff: \
flower \
$SKIP \
src_mac $SMAC \
dst_mac $DMAC \
action drop $index_str" >> ${OUT}.$n
				((count+=1))
				if (( set_prio == 1 )); then
					((prio+=1))
				fi
				let p=count%500000
				if [ $p == 0 ]; then
					((n++))
				fi
				if ((count>=num)); then
					break;
				fi
			done
			if ((count>=num)); then
				break;
			fi
		done
		if ((count>=num)); then
			break;
		fi
	done
	if ((count>=num)); then
		break;
	fi
done

$TC qdisc add dev $ETH ingress

echo "Insert rules"

time (for file in ${OUT}.*; do
	_cmd="$TC -b $file"
        echo $_cmd
        $_cmd
	ret=$?
	((ret != 0)) && echo "tc err: $ret" && exit $ret || true
done) 2>&1

exit $?
