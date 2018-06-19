#!/usr/bin/python
#
# Replay output from tc monitor
#

import os


dump="""
deleted qdisc ingress ffff: dev ens1f0 parent ffff:fff1 ---------------- 
qdisc ingress ffff: dev ens1f0 parent ffff:fff1 ----------------         
deleted qdisc ingress ffff: dev ens1f1 parent ffff:fff1 ---------------- 
qdisc ingress ffff: dev ens1f1 parent ffff:fff1 ----------------         


deleted qdisc ingress ffff: dev ens1f0_0 parent ffff:fff1 ---------------- 
qdisc ingress ffff: dev ens1f0_0 parent ffff:fff1 ----------------         
deleted qdisc ingress ffff: dev ens1f0_1 parent ffff:fff1 ---------------- 
qdisc ingress ffff: dev ens1f0_1 parent ffff:fff1 ----------------         


filter dev ens1f0_1 ingress protocol arp pref 1 flower handle 0x1                              
  dst_mac e4:11:22:28:b0:50                                                                    
  src_mac e4:11:22:28:b0:51                                                                    
  eth_type arp                                                                                 
  in_hw                                                                                        
        action order 1: mirred (Egress Redirect to device ens1f0_0) stolen                     
        index 346 ref 1 bind 1                                                                 
                                                                                               
filter dev ens1f0_0 ingress protocol ip pref 2 flower handle 0x1                               
  dst_mac e4:11:22:28:b0:51                                                                    
  eth_type ipv4                                                                                
  ip_proto udp                                                                                 
  ip_flags nofrag                                                                              
  in_hw                                                                                        
        action order 1: mirred (Egress Redirect to device ens1f0_1) stolen                     
        index 347 ref 1 bind 1                                                                 
                                                                                               
filter dev ens1f0_1 ingress protocol ip pref 2 flower handle 0x1                               
  dst_mac e4:11:22:28:b0:50                                                                    
  eth_type ipv4                                                                                
  ip_proto udp                                                                                 
  ip_flags nofrag                                                                              
  in_hw                                                                                        
        action order 1: mirred (Egress Redirect to device ens1f0_0) stolen                     
        index 348 ref 1 bind 1                                                                 
                                                                                               
filter dev ens1f0_0 ingress protocol arp pref 1 flower handle 0x1                              
  dst_mac e4:11:22:28:b0:51                                                                    
  src_mac e4:11:22:28:b0:50                                                                    
  eth_type arp                                                                                 
  in_hw                                                                                        
        action order 1: mirred (Egress Redirect to device ens1f0_1) stolen                     
        index 349 ref 1 bind 1                                                                 
                                                                                               
deleted filter dev ens1f0_1 ingress protocol arp pref 1 flower                                 
deleted filter dev ens1f0_0 ingress protocol ip pref 2 flower                                  
filter dev ens1f0_0 ingress protocol ip pref 2 flower handle 0x1                               
  dst_mac e4:11:22:28:b0:51
  eth_type ipv4
  ip_proto udp
  ip_flags nofrag
  in_hw
        action order 1: mirred (Egress Redirect to device ens1f0_1) stolen
        index 350 ref 1 bind 1

deleted filter dev ens1f0_1 ingress protocol ip pref 2 flower
filter dev ens1f0_1 ingress protocol ip pref 2 flower handle 0x1
  dst_mac e4:11:22:28:b0:50
  eth_type ipv4
  ip_proto udp
  ip_flags nofrag
  in_hw
        action order 1: mirred (Egress Redirect to device ens1f0_0) stolen
        index 351 ref 1 bind 1

"""


def parse_dump():
    cmds = []
    rule = ""
    for i in dump.splitlines():
        i = i.strip()
        if not i:
            if rule:
                cmds.append("tc" + rule)
                rule = ""
            continue

        skip = ['index', 'not_in_hw', 'in_hw']
        _skip = False
        for j in skip:
            if i.startswith(j):
                _skip = True
                break
        if _skip:
            continue

        if 'eth_type' in i:
            t = i.split()[1]
            if t != 'arp':
                t = 'ip'
            rule = rule.replace('protocol all', 'protocol '+t)
            continue

        if "mirred" in i:
            s = i.split()
            dev = s[s.index('device')+1].strip(')')
            i = "action mirred egress redirect dev " + dev

        if i.startswith('filter'):
            i = i.replace('filter ', 'filter add ')
            i = i.split()
            i = i[0:-2]
            i = ' '.join(i)
        elif i.startswith('deleted filter'):
            i = i.replace('deleted filter', 'filter del ')
            i = i.replace('protocol all', '')
        elif i.startswith('deleted qdisc'):
            #i = i.replace('deleted qdisc', 'qdisc del ')
            s = i.split()
            dev = s[s.index('dev')+1]
            i = 'qdisc del dev %s ingress' % dev
        elif i.startswith('qdisc ingress'):
            #i = i.replace('qdisc ', 'qdisc add ')
            dev = s[s.index('dev')+1]
            i = 'qdisc add dev %s ingress' % dev
        elif i.startswith('qdisc pfifo'):
            continue

        rule += " " + i
        if i.startswith('qdisc') or i.startswith('filter del'):
            cmds.append("tc" + rule)
            rule = ""

    if rule:
        cmds.append("tc" + rule)
        rule = ""

    return cmds


cmds = parse_dump()
for cmd in cmds:
    print cmd
    os.system(cmd)
