#!/bin/bash
#
# Test max rules in skip_sw and skip_hw on single port.
# Test max rules in 2 ports.
#
# Bug SW #900706: Adding 42K flows results in a fw error

NIC=${1:-ens5f0}
NIC2=${2:-ens5f1}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

set -e

for _nic in $NIC $NIC2; do
	# in case user has only one NIC
	if [[ "$_nic" == "" ]]; then
		continue
	fi
	for skip in skip_sw skip_hw; do
		for num in 30*1024 64*1024-16; do
			((num=num))
			# if set_index == 1, all filters share the same action
			for index in 0 1; do
				title "Testing $num rules $skip $_nic set_index:$index"
				sh $my_dir/tc_batch.sh $num $skip $_nic $index \
				    && success || fail
				reset_tc_nic $_nic
			done
		done
	done
done

((num=64*1024-16))
skip=skip_sw
index=0
title "Add both ports $num rules $skip"
sh $my_dir/tc_batch.sh $num $skip $NIC $index \
    && success || fail
sh $my_dir/tc_batch.sh $num $skip $NIC2 $index \
    && success || fail
reset_tc_nic $NIC
reset_tc_nic $NIC2

test_done
