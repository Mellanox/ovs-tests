#!/bin/bash
#
# Test add redirect rule from VF on esw0 to uplink on esw1 after setting multiport_esw lag port select mode
# Bug SW #2847145: [ASAP, OFED 5.5, multiport esw] Adding redirect rule PF2 -> REP fails in multiport esw mode

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_nic cx4 cx4lx cx5 cx6 cx6lx

function config() {
    set_lag_port_select_mode "multiport_esw"
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    REP2=`get_rep 0 $NIC2`
    reset_tc $NIC $REP $NIC2 $REP2
}

function cleanup() {
    set_lag_port_select_mode "queue_affinity"
    config_sriov 2
    config_sriov 0 $NIC2
    enable_switchdev
}

function add_tc_rule() {
    local dev1=$1
    local dev2=$2
    title "Add redirect rule $dev1 -> $dev2"
    tc_filter add dev $dev1 protocol ip ingress flower skip_sw action \
        mirred egress redirect dev $dev2
}

function add_tc_rules() {
    for i in $NIC $NIC2; do
        for j in $REP $REP2; do
            add_tc_rule $i $j
            add_tc_rule $j $i
        done
    done
}

trap cleanup EXIT

start_check_syndrome
set_lag_resource_allocation 1
config
add_tc_rules
reset_tc $NIC $NIC2 $REP $REP2
set_lag_resource_allocation 0
check_syndrome
trap - EXIT
cleanup
test_done