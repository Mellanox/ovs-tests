#!/bin/bash
#
# Collect machine and Open vSwitch info
# Author: Shahar Klein, Roi Dayan
#

OF="/tmp/ovs-dump-data-`hostname -s`.html"
OFZ="$OF.gz"
rm -f $OF
rm -f $OFZ

_VERSION="2"
_BLOCK=1

function put_of() {
    echo $@ >> $OF
}

function start_template() {
    put_of "<!DOCTYPE html>\
<html><head><meta charset="UTF-8"></head> \
<style> .block0, .block1 { border-top: 1px black solid; padding: 10px 0 10px 5px; } \
.block1 { background-color: #e1e1e1; } \
#index > a { padding: 0 20px; border-right: 1px #cecece solid; white-space: nowrap; } \
.endidx { margin-top: -300px; padding-bottom: 300px; display: block; } \
</style><body><h4>script version: $_VERSION</h4>"
}

function end_template() {
    put_of "</body></html>"
}

# format_output_of(full_command, id)
function format_output_of() {
    local cmd=$1
    local idx=$2
    local out=`eval $cmd 2>&1`

    if [ -n "$idx" ]; then
        endidx="end$idx"
    else
        endidx=""
    fi

    cat << EOT >> $OF
<div id="$idx" class="block$_BLOCK">
  <h2>$cmd</h2>
  <a href="#end$idx">bottom</a>
  <pre>$out</pre>
  <span class="endidx" id="$endidx"></span>
</div>
EOT
    ((_BLOCK=_BLOCK^1))
}

function start_index() {
    put_of '<div id="index">'
}

function add_index() {
    put_of '<a href="#'$1'">'$2'</a>'
}

function end_index() {
    put_of '</div><br><br><br><br>'
}

###### main #######

start_template

start_index
add_index "distro" "distro"
add_index "uname" "uname"
add_index "df" "df"
add_index "uptime" "uptime"
add_index "CPU" "CPU"
add_index "meminfo" "meminfo"
add_index "top" "top"
add_index "devlink-ver" "devlink version"
add_index "tc-ver" "tc version"
add_index "ifaces" "interfaces"
add_index "lspci" "lspci"
add_index "ethtool" "mellanox devices"
add_index "ofed" "ofed"
add_index "lsmod" "lsmod"
add_index "modinfo" "modinfo"
add_index "network" "network"
add_index "neighbors" "neighbors"
add_index "rtable" "routing table"
add_index "linkshow" "devices"
add_index "ovs_other_config" "ovs other_config"
add_index "ovs_external_ids" "ovs external_ids"
add_index "vsctlshow" "vsctl show"
add_index "dpctlshow" "dpctl show"
add_index "ovsrouteshow" "ovs/route/show"
add_index "dpctldumpflows" "dpctl dump flows"
add_index "listbr" "list br"
add_index "ofctldumpflows" "ofctl dump flows"
add_index "upcallshow" "upcall/show"
add_index "tcinfo" "tcinfo"
add_index "vswitchdlog" "vswitchd.log"
add_index "dmesg" "dmesg"
add_index "journalctl" "journalctl"
end_index

if [ -f /etc/os-release ] ; then
    format_output_of "cat /etc/os-release" "distro"
else
    format_output_of "cat /etc/redhat-release " "distro"
fi
format_output_of "uname -a" "uname"
format_output_of "df -h" "df"
format_output_of "uptime" "uptime"
format_output_of "cat /proc/cpuinfo" "CPU"
format_output_of "cat /proc/meminfo" "meminfo"
format_output_of "top -n 1 -c" "top"
format_output_of "devlink -V" "devlink-ver"
format_output_of "tc -V" "tc-ver"
format_output_of "ls -l /sys/class/net" "ifaces"
format_output_of "lspci | grep Mel" "lspci"

VENDOR_MELLANOX="0x15b3"
mdevs=`find /sys/class/net/*/device/vendor | xargs grep $VENDOR_MELLANOX | awk -F "/" '{print $5}'`
for d in $mdevs ; do
    format_output_of "ethtool -i $d" "ethtool"
    format_output_of "ethtool -k $d"
    . /sys/class/net/$d/device/uevent
    format_output_of "devlink dev eswitch show pci/$PCI_SLOT_NAME"
done

format_output_of "ofed_info" "ofed"
format_output_of "lsmod" "lsmod"
format_output_of "modinfo cls_flower mlx5_core devlink act_vlan act_tunnel_key" "modinfo"
format_output_of "ip address show" "network"
format_output_of "ip neigh show" "neighbors"
format_output_of "ip route show" "rtable"
format_output_of "ip -d link show" "linkshow"
format_output_of "ovs-vsctl get Open_vSwitch . other_config" "ovs_other_config"
format_output_of "ovs-vsctl get Open_vSwitch . external_ids" "ovs_external_ids"
format_output_of "ovs-vsctl show" "vsctlshow"
format_output_of "ovs-dpctl show" "dpctlshow"
format_output_of "ovs-appctl ovs/route/show" "ovsrouteshow"
format_output_of "ovs-dpctl dump-flows" "dpctldumpflows"
format_output_of "ovs-dpctl dump-flows --names"
format_output_of "ovs-appctl ofproto/list" "listbr"

for b in `ovs-appctl ofproto/list` ; do
    format_output_of "ovs-ofctl dump-ports-desc $b" "ofctldumpflows"
    format_output_of "ovs-ofctl dump-flows $b"
done

format_output_of "ovs-appctl upcall/show" "upcallshow"
ovsports=`ovs-dpctl show | grep port | cut -f2 -d: | cut -f1 -d"("`
for p in $ovsports ; do
    format_output_of "tc -stats filter show dev $p parent ffff:" "tcinfo"
    format_output_of "tc qdisc show dev $p" "tcinfo"
done

MAX_LINES=5000
format_output_of "tail -n $MAX_LINES /var/log/openvswitch/ovs-vswitchd.log" "vswitchdlog"
format_output_of "dmesg | tail -n $MAX_LINES" "dmesg"
format_output_of "journalctl -n $MAX_LINES" "journalctl"

end_template

gzip -9 $OF
OFZ="$OF.gz"

echo "Output file: $OFZ"
