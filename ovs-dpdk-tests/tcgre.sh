#!/bin/bash
#
# Script to temporary add TC GRE encap rule and remove it
# to make FW set GRE entropy.

PCI=$1

if [ -z $PCI ]; then
    echo "Usage: `basename $0` PCI"
    exit 1
fi

function is_bf() {
    lspci -s 00:00.0 2>/dev/null | grep -wq "PCI bridge: Mellanox Technologies"
}

# The argument can be mst device or PCI. Determine and get the full PCI.
echo $PCI | grep mst > /dev/null
if [ "$?" == "0" ]; then
    PF_PCI=`mst status | grep -A1 $PCI | tail -1 | cut -d '=' -f2 | cut -d ' ' -f1`
else
    out=`lspci -s $1 -D`
    if [ "$?" == "0" ]; then
          PF_PCI=`echo $out | cut -d ' ' -f1`
    fi
fi

if [ -z $PF_PCI ]; then
    echo "Cannot find PCI $1, please check PCI using lspci"
    exit 1
fi

# Get PF details
for dev in `ls -1 /sys/bus/pci/devices/${PF_PCI}/net/`; do
    port_name=`cat /sys/class/net/${dev}/phys_port_name 2>/dev/null`
    if [ "$port_name" == "p0" ] || [ "$port_name" == "p1" ]; then
        PF_DEV=$dev;
        PF_SWID=`cat /sys/class/net/${dev}/phys_switch_id 2>/dev/null`
        PF_INDEX=${port_name:1}
        break
    fi
done

if [ -z $PF_DEV ]; then
    echo "Could not find a netdev for PCI $PF_PCI"
    exit 1
fi

if [ -z $PF_SWID ]; then
    echo "PCI $PF_PCI, netdev $PF_DEV does not have a switchid"
    exit 1
fi

echo "PF $PF_DEV"

# Get VF0 details
for dev in `ls -1 /sys/class/net/`; do
    swid=`cat /sys/class/net/${dev}/phys_switch_id 2>/dev/null`
    if [ "$swid" != "$PF_SWID" ]; then
        continue
    fi
    port_name=`cat /sys/class/net/${dev}/phys_port_name | sed 's/c1//' 2>/dev/null`

    # In arm side, vf reps portname is pf[number]vf[number].
    if is_bf; then
        pn="pf${PF_INDEX//p}vf0"
        if [ "$pn" == "$port_name" ]; then
            VF_REP_DEV=$dev
            break
        fi
    elif [ "${port_name:0:3}" == "pf$PF_INDEX" ]; then
        VF_REP_DEV=$dev
        break
    fi
done

if [ -z $VF_REP_DEV ]; then
    echo "Could not find a VF representor netdev"
    exit 1
fi

echo "VF REP $VF_REP_DEV"

# Set fake GRE encap rule and remove it.
GRE_DEV=gre_sys
DUMMY_ROUTE_IP=111.111.111.111
ip r add ${DUMMY_ROUTE_IP}/32 dev $PF_DEV
ip link add $GRE_DEV type gretap external
tc qdisc delete dev $VF_REP_DEV ingress > /dev/null 2>&1
tc qdisc add dev $VF_REP_DEV ingress > /dev/null 2>&1

# Applying a dummy TC flow
TUNNEL_KEY_SET_DATA="action tunnel_key set
            src_ip 0.0.0.0
            dst_ip $DUMMY_ROUTE_IP
            id 999
            ttl 64
            nocsum"

tc filter add dev $VF_REP_DEV ingress protocol ip prio 1 flower skip_sw \
       $TUNNEL_KEY_SET_DATA \
       action mirred egress redirect dev $GRE_DEV

# Cleanups
tc qdisc delete dev $VF_REP_DEV ingress
ip link del dev $GRE_DEV
ip r del ${DUMMY_ROUTE_IP}/32
ip n d ${DUMMY_ROUTE_IP} dev $PF_DEV

echo "Done."
