#!/bin/bash
#
# Toggle num of vfs on one port after peer miss rules were already allocated.
# Check number of allocated peer miss rules is correct.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_mlxdump
require_mlxconfig

function dump_ports() {
    i=0 && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
    i=1 && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
}

function test_miss_rules() {
    title "Verify number of miss rules per eswitch"

    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev $NIC
    enable_switchdev $NIC2

    dump_ports
    count0=`grep -A2 VPORT /tmp/port0 | grep "dst_esw_owner_vhca_id\s*:0x1" | wc -l`
    # on port1 we expect dst vhca id 0x0 so it won't appear in the dump
    count1=`grep -A2 VPORT /tmp/port1 | grep "dst_esw_owner_vhca_id_valid\s*:0x1" | wc -l`

    # Today we allocate max possible peer miss rules instead of enabled vports.
    _expect=`fw_query_val NUM_OF_VFS`

    if [ $count0 -ne $_expect ] || [ $count1 -ne $_expect ]; then
        echo "Got $count0 miss rules on port0 and $count1 rules on port1"
        err "Expected $_expect peer miss rules on each port."
    else
        success "Got $count0 miss rules on port0 and $count1 rules on port1"
    fi

    config_sriov 0 $NIC2
}


test_miss_rules
test_done
