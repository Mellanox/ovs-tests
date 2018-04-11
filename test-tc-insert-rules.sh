#!/bin/bash
#
# 1. Test add rule without ip_proto
# 2. Test add rule with unmatched bits
#

NIC=${1:-ens5f0}
FILTER=${FILTER}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev
REP=`get_rep 0`
if [ -z "$REP" ]; then
    fail "Missing rep $rep"
fi


function tc_filter() {
    eval2 tc filter $@ && success
}

_prio=1
function prio() {
    echo "prio $_prio"
    let _prio+=1
}

function test_basic_L2_drop() {
    for skip in "" skip_sw skip_hw; do
        for nic in $NIC $REP ; do
            title "    - nic:$nic skip:$skip"
            reset_tc_nic $nic
            tc_filter add dev $nic protocol ip parent ffff: `prio` \
                    flower \
                            $skip \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                    action drop
        done
    done
}

function test_basic_L2_redirect() {
    local nic2
    for skip in "" skip_sw skip_hw; do
        nic2=$REP
        for nic in $NIC $REP ; do
            title "    - $nic -> $nic2 (skip:$skip)"
            reset_tc_nic $nic
            tc_filter add dev $nic protocol ip parent ffff: `prio` \
                    flower \
                            $skip \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                    action mirred egress redirect dev $nic2
            nic2=$NIC
        done
    done
}

function test_basic_L3() {
    for skip in "" skip_sw skip_hw; do
        for nic in $NIC $REP ; do
            title "    - nic:$nic skip:$skip"
            reset_tc_nic $nic
            tc_filter add dev $nic protocol ip parent ffff: `prio` \
                    flower \
                            $skip \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            src_ip 1.1.1.1 \
                            dst_ip 2.2.2.2 \
                    action drop
        done
    done
}

function test_basic_L3_ipv6() {
    for skip in "" skip_sw skip_hw; do
        for nic in $NIC $REP ; do
            title "    - nic:$nic skip:$skip"
            reset_tc_nic $nic
            tc_filter add dev $nic protocol ipv6 parent ffff: `prio` \
                    flower \
                            $skip \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            src_ip 2001:0db8:85a3::8a2e:0370:7334\
                            dst_ip 2001:0db8:85a3::8a2e:0370:7335 \
                    action drop
        done
    done
}

function test_basic_L4() {
    for skip in "" skip_sw skip_hw; do
        for nic in $NIC $REP ; do
            title "    - nic:$nic skip:$skip"
            reset_tc_nic $nic
            tc_filter add dev $nic protocol ip parent ffff: `prio` \
                    flower \
                            $skip \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            ip_proto tcp \
                            src_ip 1.1.1.1 \
                            dst_ip 2.2.2.2 \
                    action drop
        done
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
    tc_filter add dev $nic1 protocol 802.1Q parent ffff: `prio` \
                flower \
                        $skip \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                action vlan push id 100 \
                action mirred egress redirect dev $nic2
    title "    - vlan pop"
    tc_filter add dev $nic2 protocol 802.1Q parent ffff: `prio` \
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
        __test_basic_vlan $REP $NIC $skip
        #if [ "$skip" == "skip_sw" ]; then
        #    warn "- skip vlan skip_sw VF/outer - not supported - its ok"
        #    continue
        #fi
        #__test_basic_vlan $REP $NIC $skip
    done
}

function __test_basic_vxlan() {
    local ip_src=$1
    local ip_dst=$2
    local skip
    # note: we support adding decap to vxlan interface only.
    vx=vxlan1
    vxlan_port=4789
    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dev $NIC dstport $vxlan_port external
    ip link set dev $vx up
    tc qdisc add dev $vx ingress

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ifconfig $NIC up
    ip neigh add $ip_dst lladdr e4:11:22:11:55:55 dev $NIC

    reset_tc_nic $NIC
    reset_tc_nic $REP

    for skip in "" skip_hw skip_sw ; do
        title "- skip:$skip"
        reset_tc $REP
        reset_tc $vx
        title "    - encap"
        tc_filter add dev $REP protocol 0x806 parent ffff: `prio` \
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
        tc_filter add dev $vx protocol 0x806 parent ffff: `prio` \
                    flower \
                            $skip \
                            dst_mac e4:11:22:11:4a:51 \
                            src_mac e4:11:22:11:4a:50 \
                            enc_src_ip $ip_src \
                            enc_dst_ip $ip_dst \
                            enc_dst_port $vxlan_port \
                            enc_key_id 100 \
                    action tunnel_key unset \
                    action mirred egress redirect dev $REP
    done

    reset_tc $NIC
    reset_tc $REP
    reset_tc $vx
    ip addr flush dev $NIC
    ip link del $vx
    tmp=`dmesg | tail -n20 | grep "encap size" | grep "too big"`
    if [ "$tmp" != "" ]; then
        err "$tmp"
    fi
}

function test_basic_vxlan_ipv4() {
    __test_basic_vxlan \
                        20.1.11.1 \
                        20.1.12.1
}

function test_basic_vxlan_ipv6() {
    __test_basic_vxlan \
                        2001:0db8:85a3::8a2e:0370:7334 \
                        2001:0db8:85a3::8a2e:0370:7335
}

function test_duplicate_vlan() {
    skip="skip_sw"
    reset_tc_nic $NIC
    reset_tc_nic $REP
    start_check_syndrome
    title "- first rule"
    duplicate="filter add dev $REP protocol 802.1Q parent ffff: `prio` \
                flower \
                        $skip \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                        action vlan push id 100 \
                        action mirred egress redirect dev $NIC"
    tc $duplicate
    if [ $? != 0 ]; then
        eval err "Command failed: tc $duplicate"
    else
        success
        title "- duplicate rule"
        tc $duplicate 2>/dev/null && err "Expected to fail adding duplicate rule" || success "Failed as expected"
        expect_syndrome "0xd5ef2" && success || err "Expected a syndrome 0xd5ef2"
    fi
    reset_tc_nic $NIC
    reset_tc_nic $REP
}

function test_duplicate_vxlan() {
    skip="skip_sw"
    vx=vxlan_dup_test
    vxlan_port=4789
    ip_dst=20.1.11.1
    ip_src=20.1.12.1

    ip link del $vx >/dev/null 2>&1
    ip link add $vx type vxlan dev $NIC dstport $vxlan_port external
    ip link set dev $vx up
    tc qdisc add dev $vx ingress

    ip addr flush dev $NIC
    ip addr add $ip_src/16 dev $NIC
    ifconfig $NIC up
    ip neigh add $ip_dst lladdr e4:11:22:11:55:55 dev $NIC

    reset_tc_nic $NIC
    reset_tc_nic $REP

    start_check_syndrome
    title "- first rule"
    duplicate="filter add dev $REP protocol 0x806 parent ffff: prio 11 \
                flower \
                        $skip \
                        dst_mac e4:11:22:11:4a:51 \
                        src_mac e4:11:22:11:4a:50 \
                action tunnel_key set \
                src_ip $ip_src \
                dst_ip $ip_dst \
                id 100 \
                dst_port 4789 \
                action mirred egress redirect dev $vx"
    tc $duplicate
    if [ $? != 0 ]; then
        eval err "Command failed: tc $duplicate"
    else
        success
        title "- duplicate rule"
        tc $duplicate 2>/dev/null && err "Expected to fail adding duplicate rule" || success "Failed as expected"
        expect_syndrome "0xd5ef2" && success || err "Expected a syndrome 0xd5ef2"
    fi

    reset_tc_nic $NIC
    reset_tc_nic $REP
    ip addr flush dev $NIC
    ip link del $vx
}

# test insert ip no ip_proto
function test_insert_ip_no_ip_proto() {
    reset_tc_nic $REP
    tc_filter add dev $REP protocol ip parent ffff: `prio` \
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
    reset_tc_nic $REP
    tc_filter add dev $REP protocol ip parent ffff: `prio` \
                flower \
                        skip_sw \
			dst_mac e4:11:22:11:4a:51 \
			src_mac e4:11:22:11:4a:50 \
			src_ip 1.1.1.5/24 \
                action drop
    check_syndrome && success || err "Failed"
}

# reported in the mailing list for causing null dereference
# Possible regression due to "net/sched: cls_flower: Add offload support using egress Hardware device"
# Simon Horman <horms@verge.net.au>
# Fix commit:
# a6e169312971 net/sched: cls_flower: Set the filter Hardware device for all use-cases
function test_simple_insert_missing_action() {
    reset_tc_nic $NIC
    tc_filter add dev $NIC protocol ip parent ffff: `prio` flower indev $NIC
}


enable_switchdev_if_no_rep $REP
unbind_vfs
reset_tc_nic $NIC
reset_tc_nic $REP
stop_openvswitch

# clean vxlan interfaces
for vx in `ip -o l show type vxlan | cut -d: -f 2` ; do
    ip l del $vx
done

if [ "$DEVICE_IS_CX4" = 1 ]; then
    echo "Device is ConnectX-4. set inline-mode."
    mode=`get_eswitch_inline_mode`
    test "$mode" != "transport" && (set_eswitch_inline_mode transport || fail "Failed to set inline mode transport")
elif [ "$DEVICE_IS_CX5" = 1 ]; then
    echo "Device is ConnectX-5. no need to set inline-mode."
fi

# Execute all test_* functions
max_tests=100
count=0
for i in `declare -F | awk {'print $3'} | grep ^test_`; do
    if [ "$i" == "test_done" ]; then
        continue
    fi

    if [ -n "$FILTER" ]; then
        if [[ $i =~ $FILTER ]]; then
            : OK
        else
            continue
        fi
    fi

    if [ -n "$SKIP" ]; then
        if [[ $i =~ $SKIP ]]; then
            continue
        else
            : OK
        fi
    fi

    title $i
    eval $i

    let count=count+1
    if [ $count = max_tests ]; then
        echo "** REACHED MAX TESTS $max_tests **"
        break
    fi
done

if [ $count -eq 0 ]; then
    err "No cases were tested"
fi

reset_tc_nic $NIC
reset_tc_nic $REP
check_kasan
test_done
