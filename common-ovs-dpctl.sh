UFID="ufid:c5f9a0b1-3399-4436-b742-30825c64a1e5"

# XXX
# ovs-dpctl doesn't work as it hw-offload value is not read from other_config.
# ovs-appctl dpctl needs ufid because of a check ufid exists. why? we can generate one? function exported?

# XXX
# Adding flow gets deleted right away and in the log we used used>10.. why its not 0?
# In tc filter show used is 0.

function is_ovs_2_10() {
    ovs-vsctl --version | grep -q 2.10
}

dump_sleep=":"
if is_ofed && is_ovs_2_10 ; then
    dump_sleep="sleep 0.2"
fi

function add_flow() {
    local g=${1:-1.1.1.1}
    m=`ovs-appctl dpctl/add-flow $flow 2 ; $dump_sleep ; ovs_dump_tc_flows | grep -m1 $g`
    if [ -n "$m" ]; then
        return 0
    fi

    local tmp="ovs_dump_ovs_flows | grep -m $g"
    if [ -n "$tmp" ]; then
        echo $tmp
        err "Rule not in tc"
        return 1
    fi

    m=`ovs-appctl dpctl/add-flow $flow 2 ; $dump_sleep ; ovs_dump_tc_flows | grep -m1 $g`
    if [ -z "$m" ]; then
        err "Failed to add test flow: $flow"
        return 1
    fi
    return 0
}

function add_sw_flow() {
    local g=${1:-1.1.1.1}
    sw=`ovs-dpctl add-flow $flow 2 ; ovs-dpctl dump-flows | grep recirc | grep -m1 $g`
    [ -z "$sw" ] && sw=`ovs-dpctl add-flow $flow 2 ; ovs-dpctl dump-flows | grep recirc | grep -m1 $g`
    if [ -z "$sw" ]; then
        err "Failed to add sw flow: $flow"
        return 1
    fi
    return 0
}

function compare_with_sw_flow() {
    ovs-dpctl del-flows && sleep 0.5
    add_sw_flow
    sw2=`echo $sw | cut -d" " -f1`
    sw2=${sw2:13}
    if [ "$m" != "$sw2" ]; then
        echo flow1 $m
        echo flow2 $sw2
        err "Expected flows to be the same"
    fi
}

function compare_keys_with_sw_flow() {
    ovs-dpctl del-flows && sleep 0.5
    add_sw_flow
    keys=`echo $m | grep -o -E "[a-z0-9]+[(=]" | tr -d "=("`
    local k
    for k in $keys; do
        if ! echo $sw | grep -q $k ; then
            echo flow $m
            err "Didn't expect $k in flow"
        fi
    done
}

function verify_key_in_flow() {
    local key=$1
    verify_keys_in_flow "" $key
}

function verify_keys_in_flow() {
    local g=$1
    local keys="${@:2}"
    local key
    [ -z "$m" ] && err "Missing tc flow" && return
    ovs-dpctl del-flows && sleep 0.5
    add_sw_flow $g
    [ -z "$sw" ] && err "Missing ovs flow" && return
    for key in $keys; do
        in_m=`echo $m | grep -o "$key([^)]*)"`
        in_sw=`echo $sw | grep -o "$key([^)]*)"`
        if [ "$in_m" != "$in_sw" ]; then
            m2=`echo $m | cut -d" " -f1`
            sw2=`echo $sw | cut -d" " -f1`
            sw2=${sw2:13}
            echo flow1 $m2
            echo flow2 $sw2
            err "Expected $key() to be the same"
        fi
    done
}
