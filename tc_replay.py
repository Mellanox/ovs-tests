#!/usr/bin/python
#
# Replay output from tc monitor
#

from __future__ import print_function

import subprocess
import argparse
import sys
import os
from pprint import pprint

TC = "/usr/sbin/tc"

example_dump = """
deleted qdisc ingress ffff: dev enp8s0f0 parent ffff:fff1 ---------------- 
qdisc ingress ffff: dev enp8s0f0 parent ffff:fff1 ----------------         

deleted qdisc ingress ffff: dev enp8s0f0_0 parent ffff:fff1 ---------------- 
qdisc ingress ffff: dev enp8s0f0_0 parent ffff:fff1 ----------------         
deleted qdisc ingress ffff: dev enp8s0f0_1 parent ffff:fff1 ---------------- 
qdisc ingress ffff: dev enp8s0f0_1 parent ffff:fff1 ----------------         

filter dev enp8s0f0_1 ingress protocol arp pref 1 flower handle 0x1                              
  dst_mac e4:11:22:28:b0:50                                                                    
  src_mac e4:11:22:28:b0:51                                                                    
  eth_type arp                                                                                 
  in_hw                                                                                        
        action order 1: mirred (Egress Redirect to device enp8s0f0_0) stolen                     
        index 346 ref 1 bind 1                                                                 
                                                                                               
filter dev enp8s0f0_0 ingress protocol ip pref 2 flower handle 0x1                               
  dst_mac e4:11:22:28:b0:51                                                                    
  eth_type ipv4                                                                                
  ip_proto udp                                                                                 
  ip_flags nofrag                                                                              
  in_hw                                                                                        
        action order 1: mirred (Egress Redirect to device enp8s0f0_1) stolen                     
        index 347 ref 1 bind 1                                                                 
                                                                                               
filter dev enp8s0f0_1 ingress protocol ip pref 2 flower handle 0x1                               
  dst_mac e4:11:22:28:b0:50                                                                    
  eth_type ipv4                                                                                
  ip_proto udp                                                                                 
  ip_flags nofrag                                                                              
  in_hw                                                                                        
        action order 1: mirred (Egress Redirect to device enp8s0f0_0) stolen                     
        index 348 ref 1 bind 1                                                                 
                                                                                               
filter dev enp8s0f0_0 ingress protocol arp pref 1 flower handle 0x1                              
  dst_mac e4:11:22:28:b0:51                                                                    
  src_mac e4:11:22:28:b0:50                                                                    
  eth_type arp                                                                                 
  in_hw                                                                                        
        action order 1: mirred (Egress Redirect to device enp8s0f0_1) stolen                     
        index 349 ref 1 bind 1                                                                 
                                                                                               
deleted filter dev enp8s0f0_1 ingress protocol arp pref 1 flower                                 
deleted filter dev enp8s0f0_0 ingress protocol ip pref 2 flower                                  
filter dev enp8s0f0_0 ingress protocol ip pref 2 flower handle 0x1                               
  dst_mac e4:11:22:28:b0:51
  eth_type ipv4
  ip_proto udp
  ip_flags nofrag
  in_hw
        action order 1: mirred (Egress Redirect to device enp8s0f0_1) stolen
        index 350 ref 1 bind 1

deleted filter dev enp8s0f0_1 ingress protocol ip pref 2 flower
filter dev enp8s0f0_1 ingress protocol ip pref 2 flower handle 0x1
  dst_mac e4:11:22:28:b0:50
  eth_type ipv4
  ip_proto udp
  ip_flags nofrag
  in_hw
        action order 1: mirred (Egress Redirect to device enp8s0f0_0) stolen
        index 351 ref 1 bind 1

"""


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--verbose', '-v', action='store_true', help='verbose output')
    parser.add_argument('--file', '-f', help='input file')
    parser.add_argument('--loop', '-l', action='store_true', help='loop cmds')
    parser.add_argument('--skip-err', '-s', action='store_true', help='skip errs')
    parser.add_argument('--no-warn', '-w', action='store_true', help='hide warns')
    return parser.parse_args()


def warn(msg):
    if not args.no_warn:
        print('WARN: %s' % msg)


def parse_dump(dump):
    cmds = []
    rule = ""

    for i in dump.splitlines():
        i = i.strip()

        skip = ['index', 'not_in_hw', 'in_hw', 'Sent', 'backlog', 'cookie', 'random', 'Action statistics']
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
            rule = rule.replace('protocol all', 'protocol %s' % t)
            continue

        elif ": mirred" in i:
            s = i.split()
            dev = s[s.index('device') + 1].strip(')')
            rule += " action mirred egress redirect dev %s" % dev
            continue

        elif ": csum" in i:
            i = i.replace('(', '')
            i = i.replace(')', '')
            i = i.replace(',', '')
            i = i.split()[4:-2]
            i = ' and '.join(i)
            rule += " action csum %s" % i
            continue

        elif "pedit action" in i:
            rule += " action pedit ex"
            continue
        elif i.startswith('key #'):
            warn('fake pedit: %s' % i)
            i = i.split()
            val = iter(i[5].zfill(12))
            hdr = i[3].strip(':').split('+')
            off = hdr[1]
            hdr = hdr[0]
            if off and int(off) <= 4:
                off = "src"
            else:
                off = "dst"
            if hdr == "ipv4":
                hdr = "ip"
                #val = '.'.join(i+j for i,j in zip(val, val))
                val = "127.0.0.1"
            elif hdr == "eth":
                val = ':'.join(i+j for i,j in zip(val, val))
            rule += " munge %s %s set %s" % (hdr, off, val)
            continue

        if 'ovs-system' in i:
            # ovs probe for tc support
            continue

        if i.startswith('filter'):
            i = i.replace('filter ', 'filter add ')
            i = i.split()
            i = i[0:-2]
            i = ' '.join(i)
        elif i.startswith('added filter') or i.startswith('replaced filter'):
            i = i.replace('added filter ', 'filter add ')
            i = i.replace('replaced filter ', 'filter replace ')
            # XXX bug? in the dump. flower key should be last.
            i = i.split()
            i.remove('flower')
            i.append('flower')
            i = ' '.join(i)
        elif i.startswith('action order'):
            i = i.split()[3:]
            # gact action drop
            if 'action' in i:
                i.remove('action')
            i = 'action ' + ' '.join(i)
            # ct commit zone 6 nat src pipe
            # vs ct zone 6 nat pipe
            # remove redundant ct nat src without addr.
            # XXX bug?
            if 'nat src pipe' in i:
                i.replace('nat src pipe', 'nat pipe')
        elif i.startswith('deleted filter'):
            i = i.replace('deleted filter', 'filter del ')
            i = i.replace('protocol all', '')
            # fix bug in the dump. flower key should be last.
            i = i.split()
            i.remove('flower')
            i.append('flower')
            i = ' '.join(i)
        elif i.startswith('deleted chain'):
            # implicit on del last rule
            continue
        elif i.startswith('added chain'):
            # implicit on add first rule
            continue
        elif i.startswith('deleted qdisc'):
            #i = i.replace('deleted qdisc', 'qdisc del ')
            s = i.split()
            dev = s[s.index('dev')+1]
            i = 'qdisc del dev %s ingress' % dev
        elif i.startswith('qdisc ingress'):
            #i = i.replace('qdisc ', 'qdisc add ')
            dev = s[s.index('dev')+1]
            i = 'qdisc add dev %s ingress' % dev
        elif i.startswith('qdisc clsact'):
            #i = i.replace('qdisc ', 'qdisc add ')
            dev = s[s.index('dev')+1]
            i = 'qdisc add dev %s clsact' % dev
        elif i.startswith('key_id'):
            # tunnel_key id
            i = i.replace('key_id', 'id')
        elif i.startswith('qdisc pfifo'):
            continue
        elif i.startswith('qdisc noqueue'):
            continue
        elif i.startswith('qdisc mq'):
            continue

        not_supported = ['icmp_type', 'icmp_code', 'used_hw_stats delayed']
        _skip = False
        for j in not_supported:
            if i.startswith(j):
                warn('not supported: %s' % i)
                _skip = True
        if _skip:
            continue

        if i.startswith('qdisc') or i.startswith('filter'):
            if rule:
                # new rule
                cmds.append(TC + " %s" % rule)
                rule = ""

        rule += " %s" % i

    if rule:
        # last rule
        cmds.append(TC + " %s" % rule)
        rule = ""

#    pprint(cmds)
    return cmds


def do_cmd(cmd):
    try:
        subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as e:
        skip = ["Cannot find specified filter chain",
                "Invalid qdisc name",
                "Qdisc doesn't exists",
                "Invalid handle",
                "Cannot find device",
                "Exclusivity flag on, cannot modify",
                "Filter with specified priority/protocol not found",
                "Specified filter handle not found",
                ]
        for i in skip:
            if i in str(e.output):
                return
        skip_cmd = ["arp_sip 10.0.15.21",
                    "arp_sip 10.0.15.102",
                    ]
        for i in skip_cmd:
            if i in cmd:
                return
        print(e.output.decode().strip())
        print("^")
        print("Failed: %s" % cmd)
        if not args.skip_err:
            raise RuntimeError(e)
        print(e)
        print("-------")


def start():
    global args

    args = parse_args()
    if args.file:
        with open(args.file, "r") as f:
            dump = f.read()
    else:
        dump = example_dump

    cmds = parse_dump(dump)

    while True:
        for cmd in cmds:
            do_cmd(cmd)
        if not args.loop:
            break

    return 0


if __name__ == "__main__":
    try:
        sys.exit(start())
    except RuntimeError as e:
        sys.exit(1)
