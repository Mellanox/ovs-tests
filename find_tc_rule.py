#!/usr/bin/python

import re
import commands


TEMP = """
filter protocol ipv6 pref 1 flower
filter protocol ipv6 pref 1 flower handle 0x1
  dst_mac 33:33:00:00:00:02
  src_mac 7c:fe:90:7b:76:5c
  eth_type ipv6
  skip_hw
        action order 1: mirred (Egress Redirect to device t_br0) stolen
        index 475 ref 1 bind 1 installed 8 sec used 8 sec
        Action statistics:
        Sent 0 bytes 0 pkt (dropped 0, overlimits 0 requeues 0)
        backlog 0b 0p requeues 0

filter protocol 802.1Q pref 2 flower
filter protocol 802.1Q pref 2 flower handle 0x3
  vlan_id 10
  vlan_prio 0
  dst_mac e4:11:22:11:4a:50
  src_mac 7c:fe:90:7b:76:5c
  eth_type ipv6
  skip_hw
        action order 1:  vlan pop pipe
         index 143 ref 1 bind 1 installed 18 sec used 0 sec
        Action statistics:
        Sent 9672 bytes 94 pkt (dropped 0, overlimits 0 requeues 0)
        backlog 0b 0p requeues 0

        action order 2: mirred (Egress Redirect to device ens5f0_0) stolen
        index 473 ref 1 bind 1 installed 18 sec used 0 sec
        Action statistics:
        Sent 9672 bytes 94 pkt (dropped 0, overlimits 0 requeues 0)
        backlog 0b 0p requeues 0

filter protocol ip pref 2 flower
filter protocol ip pref 2 flower handle 0x1
  dst_mac 8e:83:a1:af:72:a2
  src_mac e4:11:22:11:4a:50
  eth_type ipv4
  skip_sw
    action order 1: tunnel_key set
    src_ip 0.0.0.0
    dst_ip 192.168.2.2
    key_id 100
    dst_port 1478 pipe
    index 220 ref 1 bind 1 installed 21 sec used 21 sec
    Action statistics:
    Sent 0 bytes 0 pkt (dropped 0, overlimits 0 requeues 0)
    backlog 0b 0p requeues 0                                                                                                                                            
                                                                                                                                                                        
    action order 2: mirred (Egress Redirect to device vxlan_sys_1478) stolen                                                                                            
    index 167 ref 1 bind 1 installed 21 sec used 0 sec                                                                                                                  
    Action statistics:                                                                                                                                                  
    Sent 9702 bytes 99 pkt (dropped 0, overlimits 0 requeues 0)                                                                                                         
    backlog 0b 0p requeues 0                                                                                                                                            
                                                                            
"""


def call(cmd):
    return TEMP.strip()
    #return commands.getoutput(cmd)
    #with open("/tmp/1.1") as f:
    #    return f.read()

def find_tc_rule(dev, src_mac, dst_mac, proto='.*', action='.*'):
    out = call("tc -s filter show dev %s" % dev)
    pat_filter = r"^protocol %s pref .* dst_mac %s\n\s*src_mac %s\n.*\n\s*action .*:\s* %s" % (proto, dst_mac, src_mac, action)
    #pat_filter = r"^protocol %s pref .* dst_mac %s\n\s*src_mac" % (proto, dst_mac)
    #pat_action = r".*\n\s*action .*: %s .*\n\s*Sent (?P<bytes>\d+) bytes (?P<pkts>\d+) pkt \(dropped (?P<drop>\d+), overlimits \d+ requeues \d+\)" % action
    pat_action = r".*\n\s*action order .* %s.*\n\s*Sent (?P<bytes>\d+) bytes (?P<pkts>\d+) pkt \(dropped (?P<drop>\d+), overlimits \d+ requeues \d+\)" % action

    for f in re.split('\n\s*filter\s*', out):
        if re.match(pat_filter, f, re.S + re.M):
            print "matched filter"
            m = re.match(pat_action, f, re.S + re.M)
            if m:
                print "matched action"
                print m.groupdict()


def test_find_tc_rule():
    dev = "ens5f0"
    src_mac = ".*"
    dst_mac = "8e:83:a1:af:72:a2"
    proto = "ip"
    action = "tunnel_key set"
    find_tc_rule(dev, src_mac, dst_mac, proto, action)


test_find_tc_rule()
