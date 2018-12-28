#!/bin/sh

nic=${1:-ens1f0}
nic2=${2:-ens1f1}
vfs=2
vms=`seq 5 6`
hv=`hostname -s`

NICS=2
MULTIPATH=1
pci=$(basename `readlink /sys/class/net/$nic/device`)

##############################################################################


if [ `uname -r` = "3.10.0" ];  then
    devlink_compat=1
elif [ `uname -r` = "3.10.0-327.el7.x86_64" ]; then
    devlink_compat=1
fi

function set_mode() {
    local pci=$(basename `readlink /sys/class/net/$1/device`)

    if [ "$devlink_compat" = 1 ]; then
        echo $2 > /sys/kernel/debug/mlx5/$pci/compat/mode
    else
        devlink dev eswitch set pci/$pci mode $2
    fi
}

function set_eswitch_inline_mode() {
    local pci=$(basename `readlink /sys/class/net/$1/device`)

    if [ "$devlink_compat" = 1 ]; then
        echo $2 > /sys/kernel/debug/mlx5/$pci/compat/inline
    else
        devlink dev eswitch set pci/$pci inline-mode $2
    fi
}

function reset_tc_nic() {
    local nic1="$1"

    echo "reset tc for $nic1"

    # reset ingress
    tc qdisc del dev $nic1 ingress >/dev/null 2>&1

    # add ingress
    tc qdisc add dev $nic1 ingress

    # activate hw offload
    if [ "$devlink_compat" != 1 ]; then
        ethtool -K $nic1 hw-tc-offload on
    fi
}

function reset_tc() {
#		tc filter del dev $nic1 parent ffff:
    for n in $nic $nic2 ; do
        for p in `ls -1d /sys/class/net/$n*`; do
            nic1=`basename $p`
            reset_tc_nic $nic1
        done
    done
}

function stop_sriov() {
    local sriov

    for n in $nic $nic2 ; do
        sriov=/sys/class/net/$n/device/sriov_numvfs
        set_mode $n legacy
        if [ -e $sriov ]; then
            echo 0 > $sriov
        fi
    done
}

function unbind() {
    echo "Unbind VFs"
    for n in $nic $nic2 ; do
        for i in `ls -1d  /sys/class/net/$n/device/virtfn*`; do
            pci=$(basename `readlink $i`)
            echo "unbind $pci"
            echo $pci > /sys/bus/pci/drivers/mlx5_core/unbind
        done
    done
}

function stop_vms() {
    echo "Stop vms"
    for i in `virsh list --name` ; do virsh -q destroy $i ; done
}

function start_vms() {
    echo "Start vms"
    for i in $vms; do virsh -q start ${hv}-00${i}-Fedora-24 ; done
}

function wait_vms() {
    echo "Wait vms"
    for i in $vms; do
        wait_vm ${hv}-00${i}
        break; # waiting for the first one
    done
}

function wait_vm() {
    local vm=$1

    for i in 1 2 3 4; do
        ping -q -w 1 -c 1 $vm && break
        sleep 10
    done

    sleep 10 ; # wait little more for lnst to be up
}

function del_ovs_bridges() {
    ovs-vsctl list-br | xargs -r -l ovs-vsctl del-br
}

function reset_ovs() {
    service openvswitch restart
    del_ovs_bridges
    ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
    service openvswitch restart
}

function clean() {
    echo "Cleanup"
    stop_vms
    reset_ovs
    reset_tc
    stop_sriov
    devlink dev eswitch set pci/$pci multipath disable
}

function warn_extra() {
    local m="$1"
    local path=`modinfo $m | grep ^filename`
    if echo $path | grep -q extra ; then
        echo "*** WARNING *** $m -> $path"
    fi
}

function reload_modules() {
    echo "Reload modules"
    local modules="mlx5_ib mlx5_core devlink cls_flower"

    if [ "$devlink_compat" = 1 ]; then
        service openibd force-restart
        return
    fi

    for m in $modules ; do
        warn_extra $m
    done
    modprobe -r $modules ; modprobe -a $modules
    set +e
}

function nic_up() {
    echo "Nic up"
    for n in $nic $nic2 ; do
        for p in `ls -1d /sys/class/net/$n*`; do
            nic1=`basename $p`
            ifconfig $nic1 up
        done
    done
}


echo "********** LOAD `basename $0` **************" > /dev/kmsg

clean
if [ "$FAST" == "" ]; then
    reload_modules
fi

echo "Enable $vfs VFs"
/labhome/roid/scripts/ovs/set-macs.sh $nic $vfs
if [ "$NICS" == "2" ]; then
    /labhome/roid/scripts/ovs/set-macs.sh $nic2 $vfs
fi

test -e /sys/class/net/$nic/device/virtfn0 && nosriov=0 || nosriov=1
if [ "$nosriov" == 1 ]; then
    echo "Missing sriov interfaces"
    exit 1
fi

nic_up
sleep 1
reset_tc

echo "Change mode to switchdev"
unbind
set_mode $nic switchdev
set_eswitch_inline_mode $nic transport
if [ "$NICS" == "2" ]; then
    set_mode $nic2 switchdev
    set_eswitch_inline_mode $nic2 transport
fi
sleep 2
nic_up
reset_tc

if [ "$WITH_VMS" == "1" ]; then
    start_vms
    wait_vms
fi
