#!/bin/bash
#
# Syndrome while inserting the same rule twice
# This reproduce an old bug RM #1250493 closed as won't fix but is fixed today.
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

skip="skip_sw"

function tc_filter() {
    tc filter $@
}

function test_basic_L2() {
    tc_filter add dev $NIC protocol ip prio 1 parent ffff: \
            flower \
                    $skip \
                    dst_mac e4:11:22:11:4a:51 \
                    src_mac e4:11:22:11:4a:50 \
            action drop
}

function test_basic_L3() {
    tc_filter add dev $NIC protocol ip prio 1 parent ffff: \
            flower \
                    $skip \
                    dst_mac e4:11:22:11:4a:51 \
                    src_mac e4:11:22:11:4a:50 \
                    src_ip 1.1.1.1 \
                    dst_ip 2.2.2.2 \
            action drop
}

function test_basic_L3_ipv6() {
    tc_filter add dev $NIC protocol ipv6 prio 1 parent ffff: \
            flower \
                    $skip \
                    dst_mac e4:11:22:11:4a:51 \
                    src_mac e4:11:22:11:4a:50 \
                    src_ip 2001:0db8:85a3::8a2e:0370:7334\
                    dst_ip 2001:0db8:85a3::8a2e:0370:7335 \
            action drop
}

function test_basic_L4() {
    tc_filter add dev $NIC protocol ip prio 1 parent ffff: \
            flower \
                    $skip \
                    dst_mac e4:11:22:11:4a:51 \
                    src_mac e4:11:22:11:4a:50 \
                    ip_proto tcp \
                    src_ip 1.1.1.1 \
                    dst_ip 2.2.2.2 \
            action drop
}


enable_switchdev

# Execute all test_* functions
for i in `declare -F | awk {'print $3'} | grep ^test_ | grep -v test_done` ; do
    title $i
    eval $i && success || err "Adding rule"
    title "- test duplicate rule fails"
    eval $i 2>/dev/null && err "Expected to fail adding duplicate rule" || success
    reset_tc_nic $nic
done

check_kasan
test_done
