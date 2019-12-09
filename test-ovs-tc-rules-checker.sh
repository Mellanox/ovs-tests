#!/bin/bash
#
# This test for commparing rules in both tc and ovs
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh

test -z "$VF2" && fail "Missing VF2"
test -z "$REP2" && fail "Missing REP2"

IP1="7.7.7.1"
IP2="7.7.7.2"

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    sleep 0.5 # wait for VF to bind back
    for i in $REP $REP2 $VF $VF2 ; do
        ifconfig $i 0 &>/dev/null
    done
    reset_tc $REP $REP2 &>/dev/null
}

function config_vf() {
    local ns=$1
    local vf=$2
    local rep=$3
    local ip=$4

    echo "$ns : $vf ($ip) -> $rep"
    ifconfig $rep 0 up
    ip netns add $ns #create new network namespace
    ip link set $vf netns $ns
    ip netns exec $ns ifconfig $vf $ip/24 up
}

enable_switchdev_if_no_rep $REP
unbind_vfs
bind_vfs

trap cleanup EXIT
cleanup
start_check_syndrome
config_vf ns0 $VF $REP $IP1
config_vf ns1 $VF2 $REP2 $IP2

start_clean_openvswitch
ovs-vsctl add-br brv-1
ovs-vsctl add-port brv-1 $REP
ovs-vsctl add-port brv-1 $REP2

tc_dump=""
ovs_dump=""

declare -a ovsArray
declare -a tcArray
declare -a sortedTcArray
declare -a sortedOvsArray

function check_src_dst() {
    for i in "${!sortedOvsArray[@]}"; do
        #check src mac
        ovs_dump=$(sed 's/,/ \\\n/g' <<<"${sortedOvsArray[i]}" | grep eth | xargs -n1 | cut -d"(" -f 2 | grep src | cut -d")" -f 1)
        tc_dump=$(echo ${sortedTcArray[i]} | grep src | xargs -n1 | cut -d"(" -f 2 | grep src | cut -d")" -f 1 )
        if [ -z "$ovs_dump" ]; then
            err "src mac of ovs dump is empty for index $i"
            return
        fi
        if [ -z "$tc_dump" ]; then
            err "src mac of tc dump is empty for index $i"
            return
        fi
        if [ "$ovs_dump" != "$tc_dump" ]; then
            err "src mac is not match for index $i"
            return
        fi
        success "src mac is match for index $i"

        #check dst mac
        ovs_dump=$(sed s/\)/\\n/g <<<"${sortedOvsArray[i]}" | grep eth | grep dst | cut -d"(" -f 2 | cut -d"," -f 2 | xargs -n1)
        tc_dump=$(echo ${sortedTcArray[i]} | cut -d"(" -f 2 | grep dst | xargs -n1)
        if [ -z "$ovs_dump" ]; then
            err "dst mac of ovs dump is empty for index $i"
            return
        fi
        if [ -z "$tc_dump" ]; then
            err "dst mac of tc dump is empty for index $i"
            return
        fi
        if [ "$ovs_dump" != "$tc_dump" ]; then
            err "dst mac is not match for index $i"
            return
        fi
        success "dst mac is match for index $i"
    done
}

function check_eth_type() {
    for i in "${!sortedOvsArray[@]}"; do
        ovs_dump=$(sed 's/,/ /g' <<<"${sortedOvsArray[i]}" | xargs -n1 | grep eth_type | cut -d"(" -f 2 | cut -d")" -f 1)
        tc_dump=$(echo ${sortedTcArray[i]} | xargs -n1 | grep eth_type | cut -d"(" -f 2 )
        if [ -z "$ovs_dump" ]; then
            err "eth type of ovs dump is empty for index $i"
            return
        fi
        if [ -z "$tc_dump" ]; then
            err "eth type of tc dump is empty for index $i"
            return
        fi
        if [ "$ovs_dump" != "$tc_dump" ]; then
            err "eth type is not match for index $i"
            return
        fi
        success "eth type is match for index $i"
    done
}

function check_offload() {
    for i in "${!sortedOvsArray[@]}"; do
        ovs_dump=$(sed 's/,/ \\\n /g' <<<"${sortedOvsArray[i]}" | grep "offloaded:yes")
        tc_dump=$(echo ${sortedTcArray[i]} | xargs -n1 | grep -w in_hw )
        if [ -z "$ovs_dump" ]; then
            continue
        fi
        if [ -z "$tc_dump" ]; then
            err "tc rule in index $i is not offloaded"
            echo ${sortedTcArray[i]}
            return
        fi
        success "offload is match for index $i"
    done
}

function check_alignment() {
    title "Check alignment"

    title "- dump ovs dp rules"
    ovs_dump=`ovs_dump_tc_flows --names -m`
    ovs_dump=$(sed 's/0x0800/ipv4/g' <<< "$ovs_dump")
    ovs_dump=$(sed 's/0x86dd/ipv6/g' <<< "$ovs_dump")
    ovs_dump=$(sed 's/0x0806/arp/g' <<< "$ovs_dump")
    ovs_dump=$(sed 's/ufid/#/g' <<< "$ovs_dump")

    title "- dump tc rules"
    tc_dump1=`tc -s filter show dev $REP ingress`
    tc_dump2=`tc -s filter show dev $REP2 ingress`
    tc_dump="$tc_dump1 $tc_dump2"

    tc_dump=$(sed 's/dst_mac /(dst=/g' <<< "$tc_dump")
    tc_dump=$(sed 's/src_mac /(src=/g' <<< "$tc_dump")
    tc_dump=$(sed 's/eth_type /eth_type(/g' <<< "$tc_dump")
    tc_dump=$(sed 's/handle/#/g' <<< "$tc_dump")

    IFS="#"
    ovsArray=(${ovs_dump:1})
    tcArray=(${tc_dump:1})
    unset IFS

    index=1
    title "- check for alignment rules"
    ovs_length=${#ovsArray[@]}
    tc_length=${#tcArray[@]}
    echo "length of ovs $ovs_length"
    echo "length of tc $tc_length"
    if [ $ovs_length -eq 0 ] || [ $tc_length -eq 0 ]; then
        err "Length of ovs or tc rules is zero"
        return
    fi
    for i in "${!ovsArray[@]}"; do
        is_match="NO"
        ufid="$(echo "${ovsArray[i]}" | egrep -o '[0-f]{8}-[0-f]{4}-[0-f]{4}-[0-f]{4}-[0-f]{12}')"
        if [ -z "$ufid" ]; then
            err "Cannot find ufid for ovs rule"
            echo "${ovsArray[i]}"
            continue
        fi
        sorted_id=$($my_dir/convert-ovs-ufid-to-tc-cookie.py $ufid)
        for j in "${!tcArray[@]}"; do
            cookie="$(echo "${tcArray[j]}" | grep -oP 'cookie \K[0-f]+' | head -1)"
            if [ -z "$cookie" ]; then
                continue
            fi
            if [ $cookie == $sorted_id ]; then
                is_match="YES"
                sortedTcArray[index]="${tcArray[j]}"
                sortedOvsArray[index]="${ovsArray[i]}"
                ((index++))
                break
            fi
        done
        if [ $is_match == "NO" ]; then
            err "ufid $ufid didn't match with any cookie!"
            echo "${ovsArray[i]}"
        fi
    done

    check_src_dst
    check_eth_type
    check_offload
}


title "Test ping $VF($IP1) -> $VF2($IP2)"
ip netns exec ns0 ping -q -c 1 -w 1 $IP2 && success || fail "Ping failed"
check_alignment

del_all_bridges
cleanup
check_syndrome
test_done
