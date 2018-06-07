#!/bin/bash
#
# Test reading stats
#
# Bug SW #1416331: reading SW stats through ifstat cause kernel crash
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


title "Test ifstat"
for i in 1 2 3 ; do
    ifstat $NIC || err "ifstat failed"
done

title "Test ifstat cpu_hits"
for i in 1 2 3 ; do
    ifstat -x cpu_hits $NIC || err "ifstat cpu_hits failed"
done

test_done
