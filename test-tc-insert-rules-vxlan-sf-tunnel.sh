#!/bin/bash
#
# Verify encap decap rules insertion on setup with SF as tunnel endpoint
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

min_nic_cx6

function test_vxlan() {
    local ip_src="20.1.11.1"
    local ip_dst="20.1.12.1"
    local vxlan_port="4789"
    local skip
    # note: we support adding decap to vxlan interface only.
    vx=vxlan1
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dev $SF dstport $vxlan_port external
    [ $? -ne 0 ] && err "Failed to create vxlan interface" && return 1
    ip link set dev $vx up
    tc qdisc add dev $vx ingress

    ip addr flush dev $SF
    ip addr add $ip_src/16 dev $SF
    ifconfig $SF up
    ip neigh replace $ip_dst lladdr e4:11:22:11:55:55 dev $SF

    for skip in "" skip_hw skip_sw ; do
        title "- skip:$skip dst_port:$vxlan_port"
        reset_tc $SF_REP
        reset_tc $vx
        title "    - encap"
        tc_filter_success add dev $SF_REP protocol 0x806 parent ffff: prio 1 \
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
            log "skip_sw on tunnel device is not supported"
            continue
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
                    action mirred egress redirect dev $SF_REP
        if [ "$skip" = "skip_hw" ]; then
            continue
        fi
        tc_filter_success show dev $vx ingress prio 2 | grep -q -w in_hw || err "Decap rule not in hw"
    done

    reset_tc $SF_REP $vx
    ip neigh del $ip_dst lladdr e4:11:22:11:55:55 dev $SF
    ip addr flush dev $SF
    ip link del $vx
    tmp=`dmesg | tail -n20 | grep "encap size" | grep "too big"`
    if [ "$tmp" != "" ]; then
        err "$tmp"
    fi
}


enable_switchdev
unbind_vfs
bind_vfs
create_sfs 1
fail_if_err "Failed to create sfs"
SF=`sf_get_netdev 1`
SF_REP=`sf_get_rep 1`
echo "SF $SF SF_REP $SF_REP"

test_vxlan

remove_sfs
test_done
