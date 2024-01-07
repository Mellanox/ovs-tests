#!/bin/bash
#
# Test OVS adding 4k openflow rules per second on a bridge with configured dpdk ports.
#
# Feature Request #3494640: [HBN] [OVS-DOCA] 4K Openflow per sec on Bluefield-3.
# Task #3659033: low openflow insertion

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

config_sriov 16
enable_switchdev
bind_vfs

function cleanup() {
    ovs_conf_remove pmd-quiet-idle
    cleanup_test
    config_sriov 2
}

trap cleanup EXIT

number_of_rules=${1:-4000}
expected_time=$((number_of_rules/1000*300))
output_file="/tmp/openflow_batch_$$"
br=br-phy
ofctl_rule_prefix="in_port=2,ip,tcp"

if [ "$short_device_name" == "bf2" ]; then
    expected_time=$((number_of_rules/1000*500))
fi


function config() {
    echo > $output_file
    ovs_conf_set pmd-quiet-idle true
    start_clean_openvswitch
    config_simple_bridge_with_rep 16
}

function copy_batch_to_bf() {
    if is_bf_host; then
        scp2 $output_file $BF_IP:/tmp/
    fi
}

function create_openflow_rules_port_change_batch() {
    title "Creating $number_of_rules openflow rules batch with port change"
    for i in `seq 1 $number_of_rules`; do
        echo "$ofctl_rule_prefix,tcp_src=$i,action=drop" >> $output_file
    done

    copy_batch_to_bf
}

function create_openflow_rules_mac_change_batch() {
    title "Creating $number_of_rules openflow rules batch with mac change"
    local mac
    local count=0

    for ((i = 0; i < 99; i++)); do
        for ((j = 0; j < 99; j++)); do
            for ((k = 0; k < 99; k++)); do
                for ((l = 0; l < 99; l++)); do
                    mac="e4:11:$i:$j:$k:$l"
                    echo "$ofctl_rule_prefix,dl_src=$mac,dl_dst=$mac,action=drop" >> $output_file
                    let count=count+1
                    [ $count -eq $number_of_rules ] && return
                done
            done
        done
    done

    copy_batch_to_bf
}

function test_time_cmd() {
    local x=$1
    local cmd=$2
    local t1=`get_ms_time`
    time $cmd || err "Command failed: $cmd"
    local t2=`get_ms_time`
    let t=t2-t1
    if [ $t -gt $x ]; then
        err "Took $t ms but expected less than $x ms"
    else
        success "took $t ms (max $x)"
    fi
}

function apply_batch() {
    title "Apply openflow rule batch"
    test_time_cmd $expected_time "ovs-ofctl add-flows $br $output_file"
    local rules=`ovs-appctl bridge/dump-flows $br | wc -l`

    if [ $rules -ge $number_of_rules ]; then
        success "Found $rules rules which is more than $number_of_rules rules"
    else
        err "Expected at least $number_of_rules rules and found only $rules rules"
    fi
}

function run() {
    config

    create_openflow_rules_port_change_batch
    apply_batch

    ovs-ofctl del-flows $br

    echo > $output_file
    create_openflow_rules_mac_change_batch
    apply_batch
}

run
trap - EXIT
cleanup
test_done
