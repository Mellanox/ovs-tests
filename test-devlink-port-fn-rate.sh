#!/bin/bash
#
# Test VF group rate limit user API with mlx5_core

my_dir="$(dirname "$0")"
. $my_dir/common.sh

pci_dev="pci/$PCI"
num_vfs=3

start_check_syndrome
config_reps $num_vfs

function dl_cmd() {
    eval2 devlink port func rate $@
}

function dl_check_attr() {
    local handle=$1
    local attr=$2
    local rate=$3
    local value

    dl_cmd set $handle $attr ${rate}mbit || return 1
    value=$(dl_cmd show $handle -j | jq '.[][].'$attr) || return 1
    value=$(( value * 8 / 1000000 ))
    [ "$value" == "$rate" ] ||
        {
            err "Expected $handle $attr $rate, got - $value"
            return 1
        }
}

function dl_check_rate() {
    local objs="$1"
    local rate="0"

    for obj in $objs;do
        dl_check_attr $obj tx_share $(( rate += 10 )) || return 1
        dl_check_attr $obj tx_max $(( rate += 10 )) || return 1
    done
}

function test_leafs_creation() {
    title "Leafs creation"
    local output=$(dl_cmd show | grep "${pci_dev}.*type leaf")
    local num_leafs=$(echo "$output" | wc -l)

    [ "$num_vfs" -eq $num_leafs ] ||
        {
            err "Expected $num_vfs leafs created, got - $num_leafs"
            return 1
        }
    echo "$output"
}

function test_leafs_deletion() {
    title "Leafs deletion"
    enable_legacy
    local output=$(dl_cmd show | grep "${pci_dev}.*type leaf")

    [ -z "$output" ] ||
        {
            err "Leafs weren't deleted:\n$output"
            return 1
        }
}

function test_leafs_set_rates() {
    title "Leafs setting tx rates"
    local leafs=$(dl_cmd show -j | jq '.[] | to_entries |
                                        .[] | select(.value.type == "leaf") |
                                        .key | select(startswith("'$pci_dev'"))')

    [ -z "$leafs" ] && err "No leafs" && return 1

    dl_check_rate "$leafs"
    local rc=$?
    dl_cmd show | grep "${pci_dev}.*type leaf"
    return $rc
}

function dl_set_parent() {
    local leaf=$pci_dev/$1
    local node=$2
    local parent

    dl_cmd set $leaf parent $node || return 1
    parent=$(dl_cmd show $leaf -j | jq -r .[][].parent)
    [ "$parent" == "$node" ] ||
        {
            err "Expected $leaf parent $node, got - '$parent'"
            return 1
        }
}

function dl_unset_parent() {
    local leaf=$pci_dev/$1
    local parent

    dl_cmd set $leaf noparent || return 1
    parent=$(dl_cmd show $leaf -j | jq -r .[][].parent)
    [ "$parent" == "null" ] ||
        {
            err "Expected $leaf noparent, got - '$parent'"
            return 1
        }
}

function test_leafs_set_parent() {
    title "Leafs parent"
    (
        set -o errexit

        echo " - parent set"
        dl_set_parent 1 1st_grp || return 1
        dl_set_parent 2 2nd_grp || return 1

        dl_cmd show | grep "${pci_dev}.*type leaf.*parent"
        success

        echo " - parent unset"
        dl_unset_parent 1 || return 1
        dl_unset_parent 2 || return 1

        dl_cmd show
        success
    )
}

function test_groups_creation() {
    title "Groups creation"
        local groups="1st_grp 2nd_grp"

    for group in $groups;do
        dl_cmd add $pci_dev/$group || return 1
        dl_cmd show $pci_dev/$group || return 1
    done
}

function test_groups_set_rates() {
    title "Groups setting tx rates"
    local groups=$(dl_cmd show -j | jq '.[] | to_entries |
                                        .[] | select(.value.type == "node") |
                                        .key | select(startswith("'$pci_dev'"))')

    [ -z "$groups" ] && err "No groups" && return 1

    dl_check_rate "$groups"
    local rc=$?
    dl_cmd show | grep "${pci_dev}.*type node"
    return $rc
}

function test_groups_creation_with_rates() {
    title "Groups creation with tx rates"
    (
        groups="3rd_grp 4th_grp"
        rate="10"

        set -o errexit
        for group in $groups;do
            dl_cmd add $pci_dev/$group tx_share ${rate}mbit tx_max $(( rate + 10 ))mbit

            output=$(dl_cmd show $pci_dev/$group -j)
            tx_share=$(echo $output | jq '.[][].tx_share')
            tx_share=$(( tx_share * 8 / 1000000 ))
            tx_max=$(echo $output | jq '.[][].tx_max')
            tx_max=$(( tx_max * 8 / 1000000 ))

            [ $tx_share -eq $rate ] && [ $tx_max -eq $(( rate + 10 )) ] ||
                {
                    err "Expected $pci_dev/$group tx_share $rate tx_max $(( rate + 10 ))" \
                        "got - tx_share $tx_share tx_max $tx_max"
                    false
                }
            ((rate+=20))
        done
        dl_cmd show | grep "${pci_dev}.*type node"
    )
}

function test_groups_deletion() {
    title "Groups deletion"
    local groups=$(dl_cmd show -j | jq '.[] | to_entries |
                                        .[] | select(.value.type == "node") |
                                        .key | select(startswith("'$pci_dev'"))')
    local ret=0

    [ -z "$groups" ] && warn "No groups to delete" && return

    for group in $groups;do
        dl_cmd del $group || ret=1
    done
    return $ret
}

test_cases="
    test_leafs_creation
    test_leafs_set_rates
    test_groups_creation
    test_groups_set_rates
    test_leafs_set_parent
    test_groups_creation_with_rates
    test_groups_deletion
    test_leafs_deletion
"


for test_case in $test_cases;do
    eval $test_case && success || err
done


check_syndrome
check_kasan

# if some tests failed they can affect next ones
if [ $TEST_FAILED != 0 ]; then
    __ignore_errors=1
    reload_modules
    __ignore_errors=0
else
    disable_sriov
fi

config_sriov
test_done
