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

function test_duplicate_vlan() {
    tc_filter add dev $REP protocol 802.1Q parent ffff: prio 11 \
                flower \
                        $skip \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                        action vlan push id 100 \
                        action mirred egress redirect dev $NIC
}

function config_vxlan() {
    vx=vxlan_dup_test
    vxlan_port=4789
    ip_dst=20.1.11.1
    ip_src=20.1.12.1

    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dev $NIC dstport $vxlan_port external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set dev $vx up
    tc qdisc add dev $vx ingress

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ifconfig $NIC up
    ip neigh add $ip_dst lladdr e4:11:22:11:55:55 dev $NIC
}

function clean_vxlan() {
    ip addr flush dev $NIC
    ip link del $vx
}

__test_vxlan=0
function test_duplicate_vxlan() {
    if [ $__test_vxlan -eq 0 ]; then
        config_vxlan || return 1
    fi
    let __test_vxlan+=1

    tc_filter add dev $REP protocol 0x806 parent ffff: prio 1 \
                flower \
                        $skip \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                action tunnel_key set \
                src_ip $ip_src \
                dst_ip $ip_dst \
                id 100 \
                dst_port 4789 \
                action mirred egress redirect dev $vx
    local rc=$?

    if [ $__test_vxlan -eq 2 ]; then
        clean_vxlan
    fi

    return $rc
}


enable_switchdev

# Execute all test_* functions
for i in `declare -F | awk {'print $3'} | grep ^test_ | grep -v test_done` ; do
    title $i
    reset_tc $NIC
    reset_tc $REP
    eval $i && success || err "Failed adding rule"
    eval $i 2>/dev/null && err "Expected to fail adding duplicate rule" || success
    reset_tc $NIC
    reset_tc $REP
done

check_kasan
test_done
