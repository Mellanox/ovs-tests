#!/bin/bash
#
# 1. Test add rule without ip_proto
# 2. Test add rule with unmatched bits
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh


function tc_filter() {
    eval2 tc filter $@ && success || err
}

function test_basic_L2() {
    for skip in "" skip_sw skip_hw; do
        title "    - skip:$skip"
        reset_tc_nic ${NIC}_0
        tc_filter add dev ${NIC}_0 protocol ip parent ffff: \
                flower \
                        $skip \
			dst_mac e4:11:22:11:4a:51 \
			src_mac e4:11:22:11:4a:50 \
                action drop
    done
}

function test_basic_L3() {
    for skip in "" skip_sw skip_hw; do
        title "    - skip:$skip"
        reset_tc_nic ${NIC}_0
        tc_filter add dev ${NIC}_0 protocol ip parent ffff: \
                flower \
                        $skip \
			dst_mac e4:11:22:11:4a:51 \
			src_mac e4:11:22:11:4a:50 \
                        src_ip 1.1.1.1 \
                        dst_ip 2.2.2.2 \
                action drop
    done
}

function test_basic_L3_ipv6() {
    for skip in "" skip_sw skip_hw; do
        title "    - skip:$skip"
        reset_tc_nic ${NIC}_0
        tc_filter add dev ${NIC}_0 protocol ipv6 parent ffff: \
                flower \
                        $skip \
			dst_mac e4:11:22:11:4a:51 \
			src_mac e4:11:22:11:4a:50 \
                        src_ip 2001:0db8:85a3::8a2e:0370:7334\
                        dst_ip 2001:0db8:85a3::8a2e:0370:7335 \
                action drop
    done
}

function test_basic_L4() {
    for skip in "" skip_sw skip_hw; do
        title "    - skip:$skip"
        reset_tc_nic ${NIC}_0
        tc_filter add dev ${NIC}_0 protocol ip parent ffff: \
                flower \
                        $skip \
			dst_mac e4:11:22:11:4a:51 \
			src_mac e4:11:22:11:4a:50 \
                        ip_proto tcp \
                        src_ip 1.1.1.1 \
                        dst_ip 2.2.2.2 \
                action drop
    done
}

function __test_basic_vlan() {
    local nic1=$1
    local nic2=$2
    local skip=$3
    title "- nic1:$nic1 nic2:$nic2 skip:$skip"
    reset_tc_nic $nic1
    reset_tc_nic $nic2
    title "    - vlan push"
    tc_filter add dev $nic1 protocol 802.1Q parent ffff: \
                flower \
                        $skip \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                action vlan push id 100 \
                action mirred egress redirect dev $nic2
    title "    - vlan pop"
    tc_filter add dev $nic2 protocol 802.1Q parent ffff: \
                flower \
                        $skip \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                        vlan_ethtype 0x800 \
                        vlan_id 100 \
                        vlan_prio 0 \
                action vlan pop \
                action mirred egress redirect dev $nic1
}

function test_basic_vlan() {
    local skip
    # real life cases:
    # 1. VF/VF no pop no push
    # 2. VF/outer push
    # 3. outer/VF pop
    for skip in "" skip_hw skip_sw ; do
        __test_basic_vlan ${NIC}_0 ${NIC} $skip
        #if [ "$skip" == "skip_sw" ]; then
        #    warn "- skip vlan skip_sw VF/outer - not supported - its ok"
        #    continue
        #fi
        #__test_basic_vlan ${NIC}_0 ${NIC} $skip
    done
}

function test_basic_vxlan() {
    local skip
    # note: we support adding decap to vxlan interface only.
    vx=vxlan1
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dstport 4789 external
    ip link set dev $vx up
    tc qdisc add dev $vx ingress
    for skip in "" skip_hw skip_sw ; do
        title "- skip:$skip"
        reset_tc_nic ${NIC}
        reset_tc_nic ${NIC}_0
        title "    - encap"
        tc_filter add dev ${NIC}_0 protocol 0x806 parent ffff: \
                    flower \
                            $skip \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                    action tunnel_key set \
                    src_ip 20.1.12.1 \
                    dst_ip 20.1.11.1 \
                    id 100 \
                    action mirred egress redirect dev ${NIC}
        title "    - decap"
        tc_filter add dev $NIC protocol 0x806 parent ffff: \
                    flower \
                            $skip \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            enc_src_ip 20.1.11.1 \
                            enc_dst_ip 20.1.12.1 \
                            enc_key_id 100 \
                            enc_dst_port 4789 \
                    action tunnel_key unset \
                    action mirred egress redirect dev ${NIC}_0
    done
    ip link del $vx
}

function test_duplicate_vlan() {
    skip="skip_sw"
    reset_tc_nic ${NIC}
    reset_tc_nic ${NIC}_0
    start_check_syndrome
    title "- first rule"
    duplicate="filter add dev ${NIC}_0 protocol 802.1Q parent ffff: \
                flower \
                        $skip \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                        vlan_ethtype 0x800 \
                        vlan_id 100"
    tc $duplicate \
                action mirred egress redirect dev ${NIC} && success || err "Failed"
    title "- duplicate rule"
    tc $duplicate \
                action mirred egress redirect dev ${NIC} && err "Expected to fail adding duplicate rule" || success "Failed as expected"
    check_syndrome && err "Expected a syndrome" || success "Syndrome as expected"
    reset_tc_nic ${NIC}
    reset_tc_nic ${NIC}_0
}

function test_duplicate_vxlan() {
    skip="skip_sw"
    reset_tc_nic ${NIC}
    reset_tc_nic ${NIC}_0
    start_check_syndrome
    title "- first rule"
    duplicate="filter add dev ${NIC}_0 protocol 0x806 parent ffff: prio 11 \
                flower \
                        $skip \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                action tunnel_key set \
                src_ip 20.1.12.1 \
                dst_ip 20.1.11.1 \
                id 100 \
                dst_port 4789"
    tc $duplicate \
                action mirred egress redirect dev ${NIC} && success || err "Failed"
    title "- duplicate rule"
    tc $duplicate \
                action mirred egress redirect dev ${NIC} && err "Expected to fail adding duplicate rule" || success "Failed as expected"
    check_syndrome && err "Expected a syndrome" || success "Syndrome as expected"
    reset_tc_nic ${NIC}
    reset_tc_nic ${NIC}_0
}

# test insert ip no ip_proto
function test_insert_ip_no_ip_proto() {
    reset_tc_nic ${NIC}_0
    tc_filter add dev ${NIC}_0 protocol ip parent ffff: \
                flower \
                        skip_sw \
			dst_mac e4:11:22:11:4a:51 \
			src_mac e4:11:22:11:4a:50 \
			src_ip 1.1.1.5 \
                action drop
    # TODO test result?
}

# test insert with bits
#[ 4021.277566] mlx5_core 0000:24:00.0: mlx5_cmd_check:695:(pid 10967): SET_FLOW_TABLE_ENTRY(0x936) op_mod(0x0) erred, status bad parameter(0x3), syndrome (0x3ad328)
#BAD_PARAM           | 0x3AD328 |  set_flow_table_entry: rule include unmatched bits (group_match_criteria == 0, but fte_match_value == 1)
function test_insert_ip_with_unmatched_bits_mask() {
    start_check_syndrome
    reset_tc_nic ${NIC}_0
    tc_filter add dev ${NIC}_0 protocol ip parent ffff: \
                flower \
                        skip_sw \
			dst_mac e4:11:22:11:4a:51 \
			src_mac e4:11:22:11:4a:50 \
			src_ip 1.1.1.5/24 \
                action drop
    title "-check syndrome"
    check_syndrome && success || err "Failed"
}

# reported in the mailing list for causing null dereference
# Possible regression due to "net/sched: cls_flower: Add offload support using egress Hardware device"
# Simon Horman <horms@verge.net.au>
function test_simple_insert_missing_action() {
    reset_tc_nic ${NIC}
    tc_filter add dev $NIC protocol ip parent ffff: flower indev $NIC
}

enable_switchdev_if_no_rep ${NIC}_0
unbind_vfs
reset_tc_nic $NIC
reset_tc_nic ${NIC}_0
mode=`get_eswitch_inline_mode`
test "$mode" != "transport" && (devlink dev eswitch set pci/$PCI inline-mode transport || fail "Failed to set mode link")

# Execute all test_* functions
for i in `declare -F | awk {'print $3'} | grep ^test_`; do
    if [ "$i" == "test_done" ]; then
        continue
    fi
    title $i
    eval $i
done

reset_tc_nic $NIC
reset_tc_nic ${NIC}_0
test_done
