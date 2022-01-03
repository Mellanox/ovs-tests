#!/bin/bash
#
# Test add hairpin rule and reload modules
#
# Bug SW #2246976: Reclaim pages call trace when unloading driver while there's SW hairpin rule.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function add_hairpin_rule() {
    local nic=$1
    local nic2=$2

    title "Add hairpin rule $nic to $nic2"
    tc_filter_success add dev $nic protocol ip parent ffff: \
          prio 1 flower skip_sw ip_proto udp \
          action mirred egress redirect dev $nic2
}

disable_sriov
enable_sriov
reset_tc $NIC $NIC2
add_hairpin_rule $NIC $NIC2
add_hairpin_rule $NIC2 $NIC
reload_modules

# wait for syndrome. noticed it after 6 seconds.
echo "Wait for syndrome"
sleep 10
reset_tc $NIC $NIC2
test_done
