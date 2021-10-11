#!/bin/bash

# Verify different geneve tunnels with the same properties, but distinct options,
# get different encap_ids. Also, check that geneve tunnels with the same
# properties and the same options, get the same encap_id.
#
# Bug SW #1903615: [Upstream] Metadata is not considered when attaching flows to Geneve encap entries

my_dir=$(dirname "$0")
. $my_dir/common.sh

local_ip="39.0.10.60"
remote_ip="39.0.10.180"
dst_mac1="e4:1d:2d:fd:81:01"
dst_mac2="e4:1d:2d:fd:82:02"
dst_mac3="e4:1d:2d:fd:83:03"
dst_port=6081
id=98

function cleanup() {
    ip link del dev geneve1 2> /dev/null
    ip n del $remote_ip dev $NIC 2>/dev/null
    ip link set $NIC down
    ip addr flush dev $NIC
    reset_tc $NIC
}

function config_geneve() {
    echo 'config geneve1 dev'
    ip link add geneve1 type geneve dstport $dst_port external
    ip link set geneve1 up
}

function add_tunnel_encap_rule() {
    local local_ip=$1
    local remote_ip=$2
    local dev=$3
    local dst_mac=$4
    local options=$5

    echo "local_ip $local_ip remote_ip $remote_ip"

    # tunnel key set
    tc_filter add dev $REP protocol ip parent ffff: prio 1 \
        flower dst_mac $dst_mac skip_sw \
        action tunnel_key set \
            id $id src_ip $local_ip dst_ip $remote_ip dst_port $dst_port geneve_opts $options nocsum \
        action mirred egress redirect dev $dev
}

function verify_encap_ids() {
    title '- verify encap ids: #1 and #2 must differ, #1 and #3 must be equal'

    local i=0
    mlxdump -d $PCI fsdump --type FT --gvmi=$i > /tmp/port$i ||
        err 'mlxdump failed'

    fte_lines=( $(grep -n FTE /tmp/port$i -m2 | cut -d: -f1) )
    encap_ids=( $(grep -e 'action.*:0x1c' -A$((fte_lines[1] - fte_lines[0])) \
                       -m3 /tmp/port$i |
                  grep packet_reformat_id | cut -d: -f2) )

    echo "encap IDs 1st-2nd: ${encap_ids[@]:0:2}"
    echo "encap IDs 2nd-3rd: ${encap_ids[@]:1:2}"

    if [[ ${encap_ids[0]} == ${encap_ids[1]} ]]; then
        err "tc filter for dst_mac1 and dst_mac2 uses the same" \
            "'packet_reformat_id': ${encap_ids[0]} (it has to be distinct)"
        return
    fi

    if [[ ${encap_ids[0]} != ${encap_ids[2]} ]]; then
        err "tc filter for dst_mac1 and dst_mac3 uses different" \
            "'packet_reformat_id': ${encap_ids[0]} and ${encap_ids[2]}" \
            "(it has to be equal)"
        return
    fi
}

function test_add_encap_rule() {
    ip n r $remote_ip dev $NIC lladdr e4:1d:2d:31:eb:08
    ip r show dev $NIC
    ip n show $remote_ip
    reset_tc $NIC $REP $dev

    add_tunnel_encap_rule $local_ip $remote_ip geneve1 $dst_mac1 '1234:56:0708090a' # unique opts
    add_tunnel_encap_rule $local_ip $remote_ip geneve1 $dst_mac2 '1234:56:a0b0c0d0' # unique opts
    add_tunnel_encap_rule $local_ip $remote_ip geneve1 $dst_mac3 '1234:56:0708090a' # same as dst_mac1

    verify_encap_ids
    reset_tc $REP
}

function do_test() {
    title $1
    eval $1
}

config_sriov 2
enable_switchdev
unbind_vfs
bind_vfs

cleanup
config_geneve
ip addr add $local_ip/24 dev $NIC
ip link set $NIC up
do_test test_add_encap_rule

cleanup
test_done
