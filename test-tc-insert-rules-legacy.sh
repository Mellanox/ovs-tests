#!/bin/bash
#
# Bug SW #1245633: [ASAP MLNX OFED] Kernel panic inserting rule in legacy mode
#

NIC=${1:-ens5f0}
FILTER=${FILTER}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


nic=$NIC
skip=""

function tc_filter() {
    eval2 tc filter $@ && success || err
}

function test_basic_L2() {
    tc_filter add dev $nic protocol ip parent ffff: \
            flower \
                    $skip \
                    dst_mac e4:11:22:11:4a:51 \
                    src_mac e4:11:22:11:4a:50 \
            action drop
}

function test_basic_L3() {
    tc_filter add dev $nic protocol ip parent ffff: \
            flower \
                    $skip \
                    dst_mac e4:11:22:11:4a:51 \
                    src_mac e4:11:22:11:4a:50 \
                    src_ip 1.1.1.1 \
                    dst_ip 2.2.2.2 \
            action drop
}

function test_basic_L3_ipv6() {
    tc_filter add dev $nic protocol ipv6 parent ffff: \
            flower \
                    $skip \
                    dst_mac e4:11:22:11:4a:51 \
                    src_mac e4:11:22:11:4a:50 \
                    src_ip 2001:0db8:85a3::8a2e:0370:7334\
                    dst_ip 2001:0db8:85a3::8a2e:0370:7335 \
            action drop
}

function test_basic_L4() {
    tc_filter add dev $nic protocol ip parent ffff: \
            flower \
                    $skip \
                    dst_mac e4:11:22:11:4a:51 \
                    src_mac e4:11:22:11:4a:50 \
                    ip_proto tcp \
                    src_ip 1.1.1.1 \
                    dst_ip 2.2.2.2 \
            action drop
}


reset_tc_nic $NIC
unbind_vfs
switch_mode_legacy

# Execute all test_* functions
for i in `declare -F | awk {'print $3'} | grep ^test_ | grep -v test_done` ; do
    title $i
    eval $i
    reset_tc_nic $nic
done

check_kasan
test_done
