#!/bin/bash
#
# Test checks that checks SF QoS group feature.
# [MLNX OFED] Bug SW #3020769: supervisor restarts when SF group is opened
# [MLNX OFED] Bug SW #3020686: [dpu_nic] server reset after running "port function rate show" on sfs
# [MLNX OFED] Bug SW #3033865: [ASAP, OFED 5.6, SF] Setting parent group for a leaf cause a call trace in mlx5_eswitch_get_vport
# [MLNX OFED] Bug SW #3033501: [ASAP, OFED 5.6, SF] syndrome 0xebf586 when setting tx_max and tx_share over SF QoS group

my_dir="$(dirname "$0")"
. $my_dir/common.sh
. $my_dir/common-sf.sh

PCI_DEV="pci/$PCI"
NUM_SFS=4

function config() {
    config_sriov 0
    enable_switchdev $NIC
    create_sfs $NUM_SFS
    fail_if_err "Failed to create sfs"
}

function check_rate() {
    local objs=$1
    local rate="1000000"

    for obj in $objs; do
        echo "set rate $rate on $obj"
        check_attr $obj tx_share $rate || return 1
        check_attr $obj tx_max $rate || return 1
    done
}

function check_attr() {
    local handle=$1
    local attr=$2
    local rate=$3
    local value

    sf_port_rate set $handle $attr $rate || (err "Failed to set rate $rate" && return 1)
    sf_port_rate show $handle
    value=$(sf_port_rate show $handle -j | jq '.[][].'$attr) || (err "Failed to get rate" && return 1)
    if [ "$value" != "$rate" ]; then
        err "Expected value of $attr to be $rate, got $value"
        return 1
    fi
    return 0
}

function test_leafs_creation() {
    title "Leafs creation"
    local output=$(sf_port_rate show | grep "${PCI_DEV}.*type leaf")
    local num_leafs=$(echo "$output" | wc -l)

    if [ "$NUM_SFS" != "$num_leafs" ]; then
        err "Expected $NUM_SFS leafs created, got $num_leafs"
        return 1
    fi

    echo "$output"
    return 0
}

function get_leafs() {
    local leafs=$(sf_port_rate show -j | jq '.[] | to_entries |
                                        .[] | select(.value.type == "leaf") |
                                        .key | select(startswith("'$PCI_DEV'"))' | xargs)
    echo $leafs
}

function get_groups() {
    local groups=$(sf_port_rate show -j | jq '.[] | to_entries |
                                        .[] | select(.value.type == "node") |
                                        .key | select(startswith("'$PCI_DEV'"))' | xargs)
    echo $groups
}

function test_leafs_set_rates() {
    title "Leafs setting tx rates"
    local leafs=$(get_leafs)

    [ -z "$leafs" ] && err "No leafs" && return 1

    check_rate "$leafs"
    local rc=$?
    sf_port_rate show | grep "${PCI_DEV}.*type leaf"
    return $rc
}

function test_groups_creation() {
    title "Groups creation"
        local groups="1st_grp 2nd_grp"

    for group in $groups; do
        sf_port_rate add $PCI_DEV/$group || return 1
        sf_port_rate show $PCI_DEV/$group || return 1
    done
}

function test_groups_set_rates() {
    title "Groups setting tx rates"
    local groups=$(get_groups)

    [ -z "$groups" ] && err "No groups" && return 1

    check_rate "$groups"
    local rc=$?
    sf_port_rate show | grep "${PCI_DEV}.*type node"
    return $rc
}

function set_parent() {
    local leaf=$1
    local node=$2
    local parent

    sf_port_rate set $leaf parent $node || (err "Failed to set parent" && return 1)
    sf_port_rate show $leaf
    parent=$(sf_port_rate show $leaf -j | jq -r .[][].parent | xargs)
    if [ "$parent" != "$node" ]; then
        err "Expected $leaf parent $node, got $parent"
        return 1
    fi
}

function unset_parent() {
    local leaf=$1
    local parent

    sf_port_rate set $leaf noparent || (err "Failed to remove parent" && return 1)
    parent=$(sf_port_rate show $leaf -j | jq -r .[][].parent | xargs)
    if [ "$parent" != "null" ]; then
        err "Expected $leaf without parent, got $parent"
        return 1
    fi
}

function test_leafs_set_parent() {
    title "Leafs parent"
    (
        set -o errexit

        echo " - parent set"
        local leafs=$(get_leafs)
        local first_leaf=$(echo $leafs| awk '{print $1}')
        local second_leaf=$(echo $leafs| awk '{print $2}')

        set_parent $first_leaf 1st_grp || return 1
        set_parent $second_leaf 2nd_grp || return 1

        sf_port_rate show | grep "${PCI_DEV}.*type leaf.*parent"
        success

        echo " - parent unset"
        unset_parent $first_leaf || return 1
        unset_parent $second_leaf || return 1

        sf_port_rate show
        success
    )
}

function test_groups_deletion() {
    title "Groups deletion"
    local groups=$(get_groups)
    local ret=0

    [ -z "$groups" ] && warn "No groups to delete" && return

    for group in $groups; do
        sf_port_rate del $group || ret=1
    done

    return $ret
}

function run() {
    test_cases="
        test_leafs_creation
        test_leafs_set_rates
        test_groups_creation
        test_groups_set_rates
        test_leafs_set_parent
        test_groups_deletion
    "

    for test_case in $test_cases; do
        eval $test_case && success || err "Test case $test_case failed"
    done
}

trap remove_sfs EXIT
config
run
remove_sfs
trap - EXIT
test_done
