#!/bin/bash
#
#

NIC=${1:-ens5f0}
NIC2=${2:-ens5f1}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

CASE_COUNT=${CASE_COUNT:-30*1024 64*1024-16}
TIMEOUT=30s

function do_test()
{
    for _nic in $NIC; do
            # in case user has only one NIC
            if [[ "$_nic" == "" ]]; then
                    continue
            fi
            for skip in skip_sw; do
                    for num in $CASE_COUNT; do
                            ((num=num))
                            # if set_index == 1, all filters share the same action
                            for index in 0 1; do
                                    title "Testing $num rules $skip $_nic set_index:$index"
                                    timeout $TIMEOUT sh $my_dir/tc_batch.sh $num $skip $_nic $index \
                                        && success || rc=$? && err
                                    echo "cleanup"
                                    reset_tc_nic $_nic
                                    if [ "$rc" == "124" ]; then
                                        err "Timed out after $TIMEOUT"
                                        return
                                    fi
                            done
                    done
            done
    done
}

do_test
test_done
