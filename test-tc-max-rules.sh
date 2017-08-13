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

CASE_SKIP=${CASE_SKIP:-skip_hw skip_sw}
CASE_COUNT=${CASE_COUNT:-30*1024 64*1024-16}
CASE_INDEX=${CASE_INDEX:-0 1}

for _nic in $NIC $NIC2; do
	# in case user has only one NIC
	if [[ "$_nic" == "" ]]; then
		continue
	fi
	for skip in $CASE_SKIP; do
		for num in $CASE_COUNT; do
			((num=num))
			# if set_index == 1, all filters share the same action
			for index in $CASE_INDEX; do
				title "Testing $num rules $skip $_nic set_index:$index"
				sh $my_dir/tc_batch.sh $num $skip $_nic $index \
				    && success || fail
				echo "cleanup"
				reset_tc_nic $_nic
			done
		done
	done
done

((num=64*1024-16))
skip=skip_sw
index=0
title "Add both ports $num rules $skip set_index:$index"
sh $my_dir/tc_batch.sh $num $skip $NIC $index \
    && success || fail
sh $my_dir/tc_batch.sh $num $skip $NIC2 $index \
    && success || fail
reset_tc_nic $NIC
reset_tc_nic $NIC2

test_done
