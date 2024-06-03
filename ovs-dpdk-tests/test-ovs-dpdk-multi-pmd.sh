#!/bin/bash
#
# Test OVS-DOCA multi-pmd traffic
#
# Require external server
#

my_dir="$(dirname "$0")"
. $my_dir/common-dpdk.sh

require_remote_server

config_sriov 2
enable_switchdev
bind_vfs

trap cleanup_test EXIT

function config() {
    cleanup_test
    config_simple_bridge_with_rep 1
    config_ns ns0 $VF $LOCAL_IP
    ovs-vsctl --timeout=$OVS_VSCTL_TIMEOUT set o . other_config:pmd-cpu-mask=0x6
    restart_openvswitch_nocheck
}

function get_stat_val() {
    local stats=$1
    local stat=$2
    local val=0
    local tok

    tok=1
    while [ 1 ]; do
        str=`echo $stats | cut -d ',' -f$tok`
        tok=$((tok+1))
        if [[ "$str" != *=* ]]; then
            break
        fi
        echo "$str" | grep $stat > /dev/null
        if [ "$?" != "0" ]; then
            continue
        fi
        val=`echo $str | cut -d '=' -f2`
        break
    done

    echo $val
}

function validate() {
    local pci=`get_pf_pci`
    local port=`get_port_from_pci $pci`
    local msg

    stats=`ovs-vsctl list int $port | grep statistics`
    debug "$stats"

    q0=`get_stat_val "$stats" "rx_q0_packets"`
    q1=`get_stat_val "$stats" "rx_q1_packets"`
    ratio=`echo "100 * $q0 / $q1" | bc`

    msg="q0=$q0, q1=$q1, ratio=$ratio"
    debug "$msg"
    if [ "$q0" -lt 40 ] || [ "$q1" -lt 40 ] || [ "$ratio" -lt 90 ] || [ "$ratio" -gt 110 ]; then
        err "$msg"
    fi
}

function run() {
    local pci=`get_pf_pci`
    local port=`get_port_from_pci $pci`
    local pktgen="$DPDK_DIR/../scapy-traffic-tester.py"
    local scapy_cmd

    config
    config_remote_nic
    sleep 5

    scapy_cmd=""
    scapy_cmd+="$pktgen -i $NIC --src-ip 1.1.1.1 --dst-ip 1.1.1.1 --inter 0"
    scapy_cmd+=" --dst-port-count=100 --pkt-count=1 --client-only"
    debug "$scapy_cmd"
    on_remote "$scapy_cmd"
    sleep 3
}

run
validate

trap - EXIT
ovs-vsctl --no-wait remove o . other_config pmd-cpu-mask
cleanup_test
test_done
