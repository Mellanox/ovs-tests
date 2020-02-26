#!/bin/bash
#
# Verify ethtool basic functionality for representors

my_dir="$(dirname "$0")"
. $my_dir/common.sh

echo "setup"
config_sriov 2 $NIC
enable_switchdev_if_no_rep $REP

require_interfaces NIC
reset_tc $NIC

declare -A counters
counters=( ["tso"]="tx_tso_"
           ["lro"]="_lro_"
           ["csum"]="_csum_"
           ["xdp"]="_xdp_"
           ["cache"]="_cache_"
           ["ecn"]="_ecn_"
           ["cqe"]="_cqe_"
           ["rx_vport"]="rx_vport_"
           ["tx_vport"]="tx_vport_"
           ["module"]="module_"
           ["ch0"]="ch0_"
           ["rx0"]="rx0_"
           ["tx0"]="tx0_"
           ["rx_out_of_buffer"]="rx_out_of_buffer"
           ["rx_if_down_packets"]="rx_if_down_packets" )

function test_stats()
{
    title "Test uplink representor extended stats groups"
    for counter_group in "${!counters[@]}"
    do
        ethtool -S $NIC | grep -q "${counters[$counter_group]}" || err "No $counter_group counters"
    done
}

function test_rss()
{
    local num_rings=4
    local hkey="00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00"

    title "Test uplink representor RSS"

    ethtool -L $NIC combined $num_rings || err "Failed to set num RX rings"
    ethtool -x $NIC | grep -q "RX flow hash indirection table for $NIC with $num_rings RX ring(s)" || err "Number of RX rings is different from the number that was set by previous command"

    ethtool -X $NIC equal 2 || err "Failed to set indirect table size"
    ethtool -x $NIC | grep -q "0:      0     1     0     1     0     1     0     1" || err "Indirect table size is not equal to size that was set by previous command"

    ethtool -X $NIC hfunc xor || err "Failed to set hfunc"
    ethtool -x $NIC | grep -q "xor: on" || err "Used hfunc type is not equal to hfunc set by previous command"

    ethtool -X $NIC hkey $hkey || err "Failed to set hkey"
    ethtool -x $NIC | grep -q $hkey || err "Used hkey is not equal to hkey set by previous command"
}

test_stats
test_rss

test_done
