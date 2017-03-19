#!/bin/sh
#
# Test max rules in skip_sw and skip_hw on single port.
# Test max rules in 2 ports.
#
# Bug SW #900706: Adding 42K flows results in a fw error

NIC=${1:-ens5f0}
NIC2=${2:-ens5f1}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

reset_tc_nic $NIC
reset_tc_nic $NIC2
set -e

title "Testing 8K skip_hw"
reset_tc_nic $NIC
sh $my_dir/tc_batch.sh 8192 skip_hw
tc -b /tmp/tc_add_batch_8192 && success || fail

title "Testing 8K skip_sw"
reset_tc_nic $NIC
sh $my_dir/tc_batch.sh 8192 skip_sw
tc -b /tmp/tc_add_batch_8192 && success || fail

title "Testing 30K skip_sw per port"
((count=30*1024))
reset_tc_nic $NIC
reset_tc_nic $NIC2
title " - Add 30K to port 1"
sh $my_dir/tc_batch.sh $count skip_sw $NIC
tc -b /tmp/tc_add_batch_$count && success || fail
title  " - Add 30K to port 2"
sh $my_dir/tc_batch.sh $count skip_sw $NIC2
tc -b /tmp/tc_add_batch_$count && success || fail
title " - cleanup"
reset_tc_nic $NIC
reset_tc_nic $NIC2

title "Testing 64K skip_hw"
reset_tc_nic $NIC
sh $my_dir/tc_batch.sh 65536 skip_hw
tc -b /tmp/tc_add_batch_65536 && success || fail

title "Testing 64K skip_sw"
reset_tc_nic $NIC
sh $my_dir/tc_batch.sh 65536 skip_sw
tc -b /tmp/tc_add_batch_65536 && success || fail

reset_tc_nic $NIC
echo "done"
