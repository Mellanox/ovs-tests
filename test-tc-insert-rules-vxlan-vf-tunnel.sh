#!/bin/bash
#
# Verify encap decap rules insertion on setup with VF as tunnel endpoint
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

function test_vxlan() {
    local ip_src="20.1.11.1"
    local ip_dst="20.1.12.1"
    local vxlan_port="4789"
    local skip
    # note: we support adding decap to vxlan interface only.
    vx=vxlan1
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dev $VF1 dstport $vxlan_port external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set dev $vx up
    tc qdisc add dev $vx ingress

    ip addr flush dev $VF1
    ip addr add $ip_src/16 dev $VF1
    ifconfig $VF1 up
    ip neigh replace $ip_dst lladdr e4:11:22:11:55:55 dev $VF1
    ifconfig $NIC up

    reset_tc $NIC $REP

    for skip in "" skip_hw skip_sw ; do
        skip_sw_wa=0
        title "- skip:$skip dst_port:$vxlan_port"
        reset_tc $REP
        reset_tc $vx
        title "    - encap"
        tc_filter_success add dev $REP protocol 0x806 parent ffff: prio 1 \
                    flower \
                            $skip \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                    action tunnel_key set \
                    src_ip $ip_src \
                    dst_ip $ip_dst \
                    dst_port $vxlan_port \
                    id 100 \
                    action mirred egress redirect dev $vx
        title "    - decap"
        if [ "$skip" = "skip_sw" ]; then
            # skip_sw on tunnel device is not supported
            skip=""
            skip_sw_wa=1
        fi
        tc_filter_success add dev $vx protocol 0x806 parent ffff: prio 2 \
                    flower \
                            $skip \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            enc_src_ip $ip_dst \
                            enc_dst_ip $ip_src \
                            enc_dst_port $vxlan_port \
                            enc_key_id 100 \
                    action tunnel_key unset \
                    action mirred egress redirect dev $REP
        if [ $skip_sw_wa -eq 1 ]; then
            tc_filter_success show dev $vx ingress prio 2 | grep -q -w in_hw || err "Decap rule not in hw"
        fi
    done

    reset_tc $NIC $REP $vx
    ip neigh del $ip_dst lladdr e4:11:22:11:55:55 dev $VF1
    ip addr flush dev $VF1
    ip link del $vx
    tmp=`dmesg | tail -n20 | grep "encap size" | grep "too big"`
    if [ "$tmp" != "" ]; then
        err "$tmp"
    fi
}


enable_switchdev
unbind_vfs
bind_vfs
require_interfaces NIC REP
start_check_syndrome

test_vxlan

check_for_errors_log
check_syndrome
check_kasan
test_done
