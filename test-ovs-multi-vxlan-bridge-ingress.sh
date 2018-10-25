#!/bin/bash
#
# Test OVS with multi vxlan bridges
#
# Bug SW #1541165: [OVS 2.10] restart OVS with two vxlan bridges cause vxlan qdisc to be deleted
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


start_clean_openvswitch

title "Test first bridge"
ovs-vsctl add-br ov1
ovs-vsctl add-port ov1 vxlan1 -- set interface vxlan1 type=vxlan options:key=42 options:remote_ip=1.1.1.1 options:dst_port=4789
tc qdisc show dev vxlan_sys_4789 ingress | grep -q ingress || err "Missing qdisc ingress on vxlan_sys_4789"

title "Test second bridge"
ovs-vsctl add-br ov2
ovs-vsctl add-port ov2 vxlan2 -- set interface vxlan2 type=vxlan options:key=42 options:remote_ip=2.1.1.1 options:dst_port=4789
tc qdisc show dev vxlan_sys_4789 ingress | grep -q ingress || err "Missing qdisc ingress on vxlan_sys_4789"

del_all_bridges
test_done
