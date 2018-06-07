#!/bin/bash
#
# Test reading stats
#
# Bug SW #1416331: reading SW stats through ifstat cause kernel crash
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

# issue was when VFs are bound so this is important.
bind_vfs

title "Test ifstat"
ifstat $NIC || err "ifstat failed"
ifstat $NIC || err "ifstat failed"

title "Test ifstat cpu_hits"
ifstat -x cpu_hits $NIC || err "ifstat cpu_hits failed"
ifstat -x cpu_hits $NIC || err "ifstat cpu_hits failed"

test_done
