#!/bin/bash

function config_ports() {
    config_sriov 2
    config_sriov 2 $NIC2
    enable_switchdev
    enable_switchdev $NIC2
    # need to unbind vfs to create/destroy vf lag
    unbind_vfs
    unbind_vfs $NIC2
}

function deconfig_ports() {
    # need to unbind vfs to create/destroy vf lag
    start_check_syndrome
    unbind_vfs
    unbind_vfs $NIC2
    # disabling sriov will cause a syndrome when destroying vf lag that we need
    # to be lag master. instead just move to legacy.
    enable_legacy $NIC2
    check_syndrome
}

function dmesg_chk() {
    local tst="$1"
    local emsg="$2"
    sleep 0.5
    a=`dmesg | tail -n6 | grep "$tst"`
    if [ $? -ne 0 ]; then
        err $emsg
        return 1
    else
        success2 $a
        return 0
    fi
}

function vf_lag_is_active() {
    dmesg_chk "modify lag map port 1:1 port 2:2" "vf lag is not active"
}

out_dev=dummy9
dev1=$NIC
dev2=$NIC2
dev1_ip=48.2.10.60
dev2_ip=48.1.10.60
n1=48.2.10.1
n2=48.1.10.1
n_mac="e4:1d:2d:31:eb:08"

function config_multipath_route() {
    echo "config multipath route"
    ip l add dev $out_dev type dummy &>/dev/null
    ifconfig $out_dev $local_ip/24
    ifconfig $dev1 $dev1_ip/24
    ifconfig $dev2 $dev2_ip/24
    ip r r $net nexthop via $n1 dev $dev1 nexthop via $n2 dev $dev2
    ip n del $n1 dev $dev1 &>/dev/null
    ip n del $n2 dev $dev2 &>/dev/null
    ip n del $remote_ip dev $dev1 &>/dev/null
    ip n del $remote_ip dev $dev2 &>/dev/null
    ip n add $n1 dev $dev1 lladdr $n_mac
    ip n add $n2 dev $dev2 lladdr $n_mac
}

function no_encap_rules() {
    local i=$1
    local a

    i=$i && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
    a=`cat /tmp/port$i | tr -d ' ' | grep "action:0x1c"`

    if [ -z "$a" ]; then
        success2 "no encap rule on port$i"
    else
        err "Didn't expect an encap rule on port$i"
    fi
}

function look_for_encap_rules() {
    local ports=$@
    local i
    local a

    for i in $ports ; do
        i=$i && mlxdump -d $PCI fsdump --type FT --gvmi=$i --no_zero > /tmp/port$i || err "mlxdump failed"
        a=`cat /tmp/port$i | tr -d ' ' | grep "action:0x1c"`

        if [ -z "$a" ]; then
            err "Cannot find encap rule in port$i"
        else
            success2 "found encap rule on port$i"
        fi
    done
}
