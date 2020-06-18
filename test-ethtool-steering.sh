#!/bin/bash
#
# Verify ethtool steering functionality

my_dir="$(dirname "$0")"
. $my_dir/common.sh

not_relevant_for_cx4
not_relevant_for_cx4lx

echo "setup"
config_sriov
enable_switchdev
require_interfaces NIC

max_ch=$(ethtool -l $NIC | grep Combined | head -1 | cut -f2-)
# max_rules is hard coded 1024 in en_fs_ethtool.c:MAX_NUM_OF_ETHTOOL_RULES
# but we could fail with resource busy and need to try again.
# to check less.
max_rules=1024
max_rules_to_test=500

function get_num_of_rules() {
    ethtool -u $NIC | grep Total | cut -d ' ' -f 2
}

function clear_num_rules() {
    local target=$1

    for i in `seq 0 $(( target - 1))`; do
        ethtool -U $NIC delete $i 2>/dev/null
    done
}

function verify_num_of_rules() {
    local current=$(get_num_of_rules)
    local target=${1:-0}
    local failed=0

    [ "$current" == "$target" ] && success || failed=1
    if [ "$failed" == 1 ]; then
        err "Wrong number of rules - $current (expected $target)"
        return 1
    fi
}

function cleanup() {
    title "cleanup"

    local num_of_channels=$(ethtool -l $NIC | grep Combined | tail -1 | cut -f2-)

    [ $num_of_channels -ne $max_ch ] && eval2 ethtool -L $NIC combined $max_ch
    [ "$(get_num_of_rules)" != "0" ] && clear_num_rules $max_rules
    eval2 ethtool -u $NIC || return 1
}

function test_max_rules() {
    title "Test inserting/deleting of $max_rules_to_test rules"

    verify_num_of_rules || return
    echo "inserting..."
    for i in `seq 0 $(( max_rules_to_test - 1 ))`; do
        eval2 ethtool -U $NIC flow-type tcp4 src-port 1 action -1 loc $i || break
    done
    verify_num_of_rules $max_rules_to_test
    echo "deleting..."
    clear_num_rules $max_rules
    verify_num_of_rules
}

function test_max_channels() {
    title "Test inserting on different channels"

    verify_num_of_rules || return
    echo "inserting..."
    for i in `seq 0 $(( max_ch - 1))`; do
        eval2 ethtool -U $NIC flow-type tcp4 src-port 1 action $i loc $i || break
    done
    verify_num_of_rules $max_ch
    echo "deleting..."
    clear_num_rules $max_ch
    verify_num_of_rules
}

# ethtool command did not return any error code itself, when driver fail,
# so eth_scs() & eth_fail() check stderr output
function eth_scs() {
    local output=$(ethtool -U $@ 2>&1)
    local failed=0

    [ -n "$output" ] && failed=1
    if [ "$failed" == "1" ]; then
        err "Command failed ($output): $@"
        return 1
    fi
}

function eth_fail() {
    local output=$(ethtool -U $@ 2>&1)

    if [ -z "$output" ]; then
        err "Expected error message '$expected_error'"
    else
        [ "${output##*: }" != "$expected_error" ] && err $output
    fi
}

function verify_mask_val() {
    local err

    ethtool -u $NIC | grep "$@" >/dev/null
    err=$?
    [ $err -ne '0' ] && err "No match: \"$@\""
}

function test_supported_flow_types() {
    title "Test supported fields and values"

    eth_scs $NIC flow-type ether src 11:22:33:44:55:66 m ff:00:ff:00:ff:00 \
        dst 66:55:44:33:22:11 m 00:ff:00:ff:00:ff proto 0x123 m 0xff action 1 loc 0 || return

    verify_mask_val 'Src MAC addr: 11:22:33:44:55:66 mask: FF:00:FF:00:FF:00'
    verify_mask_val 'Dest MAC addr: 66:55:44:33:22:11 mask: 00:FF:00:FF:00:FF'
    verify_mask_val 'Ethertype: 0x123 mask: 0xFF'

    eth_scs $NIC flow-type ip4 src-ip 1.1.1.1 m 240.0.0.0 \
        dst-ip 10.1.1.1 m 128.0.0.0 l4proto 15 m 0xf0 action 1 loc 1

    verify_mask_val 'Src IP addr: 1.1.1.1 mask: 240.0.0.0'
    verify_mask_val 'Dest IP addr: 10.1.1.1 mask: 128.0.0.0'
    verify_mask_val 'Protocol: 15 mask: 0xf0'

    eth_scs $NIC flow-type tcp4 src-port 123 m 0xff00 dst-port 456 m 0xf000 action 1 loc 2

    verify_mask_val 'Src port: 123 mask: 0xff00'
    verify_mask_val 'Dest port: 456 mask: 0xf000'

    eth_scs $NIC flow-type udp6 src-port 456 m 0xf000 dst-port 123 m 0xff00 action 1 loc 3

    verify_mask_val 'Src port: 456 mask: 0xf000'
    verify_mask_val 'Dest port: 123 mask: 0xff00'

    eth_scs $NIC flow-type ip6 src-ip ::e611:22ff:fe33:4450 m 2001:db8:abcd:12:0:0:0:0 \
        dst-ip ::e611:22ff:fe33:4450 m ffff::0:0:0:0:0:0 l4proto 12 m 0xf0 action 1 loc 4

    verify_mask_val 'Src IP addr: ::e611:22ff:fe33:4450 mask: 2001:db8:abcd:12::'
    verify_mask_val 'Dest IP addr: ::e611:22ff:fe33:4450 mask: ffff::'
    verify_mask_val 'Protocol: 12 mask: 0xf0'

    verify_num_of_rules 5
    clear_num_rules 5
}

function test_overflows() {
    title "Test overflow values of rules & channels"

    verify_num_of_rules

    title "- check rule location max rules"
    expected_error="No space left on device"
    eth_fail $NIC flow-type tcp4 src-port 1 action -1 loc $max_rules
    verify_num_of_rules

    title "- check rule action max channel"
    expected_error="Invalid argument"
    eth_fail $NIC flow-type tcp4 src-port 1 action $max_ch loc 1
    verify_num_of_rules

    title "- check channel > current num of channels"
    eval2 ethtool -L $NIC combined 2
    eth_fail $NIC flow-type tcp4 src-port 1 action 3 loc 2
    eval2 ethtool -L $NIC combined $max_ch

    verify_num_of_rules
}

function verify_hash() {
    local type=$1
    local exp_lines=$2
    local out_lines=$(ethtool -u $NIC rx-flow-hash $type | wc -l)

    [ $exp_lines -ne $out_lines ] && err "Expected $exp_lines lines. in output $out_lines lines"
}

function test_rx_flow_hash() {
    title "Test rx-flow-hash layers"
    eth_scs $NIC rx-flow-hash tcp4 sdfn || return
    verify_hash tcp4 6
    eth_scs $NIC rx-flow-hash udp4 sdfn
    verify_hash udp4 6
    eth_scs $NIC rx-flow-hash tcp6 sdfn
    verify_hash tcp6 6
    eth_scs $NIC rx-flow-hash udp6 sdfn
    verify_hash udp6 6
}

#tests for flow-type
cleanup
if [ $? != 0 ]; then
    fail "ethtool steering is probably not supported"
fi
test_max_rules
test_max_channels
test_supported_flow_types
test_overflows
cleanup

test_rx_flow_hash

test_done
