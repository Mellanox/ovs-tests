#!/usr/bin/python

import os
import sys
import argparse
import time
from scapy.all import *


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('-l', action='store_true',
                        help='Listener')
    parser.add_argument('--dev', '-i',
                        help='Device to use')
    parser.add_argument('--src-ip',
                        help='Source ip')
    parser.add_argument('--dst-ip',
                        help='Destination ip')
    parser.add_argument('--src-port', type=int, default=1026,
                        help='Source port')
    parser.add_argument('--src-port-count', type=int, default=1,
                        help='Dource port count. helper to get more streams.')
    parser.add_argument('--dst-port', type=int, default=3000,
                        help='Destination port')
    parser.add_argument('--pkt-count', type=int, default=10,
                        help='Packet count')
    parser.add_argument('--time', type=int, default=10,
                        help='Time in seconds to run client. Issue packet count per second.')

    args = parser.parse_args()
    return args


def verify_args(args, needed):
    err = False
    for i in needed:
        v = getattr(args, i)
        if not v:
            v = '(Missing)'
            err = True
        print '%s: %s' % (i, v)

    if err:
        sys.exit(1)


def run_listener(args):
    print "Run as listener"

    needed = ('dev', 'src_ip')
    verify_args(args, needed)

    #ifname='vxlan1'
    #src_ip='1.1.1.7'
    ifname = args.dev
    src_ip = args.src_ip

    # ignore icmp unreachable packets
    os.system("iptables -I OUTPUT -p icmp --icmp-type destination-unreachable -j DROP")

    def packet_fwd(pkt):
        send(IP(dst=pkt[IP].src, src=pkt[IP].dst)/
                UDP(dport=pkt[UDP].sport, sport=pkt[UDP].dport)/
                    "BBBBBBBBBBBBBBBBBBBBBBBBBBBB", verbose=0, iface=ifname)
        sys.stdout.write(',')
        sys.stdout.flush()

    filter1 = "udp and src host %s" % src_ip
    print "Start sniff and fwd on %s" % ifname
    print "filter: %s" % filter1
    sniff(iface=ifname, prn=packet_fwd, filter=filter1)


def run_client(args):
    print "Run as client"

    needed = ('dev', 'src_ip', 'dst_ip', 'src_port', 'src_port_count', 'dst_port', 'pkt_count', 'time')
    verify_args(args, needed)

    src_port_count = args.src_port_count
    packet_count = args.pkt_count

    # ignore icmp unreachable packets
    os.system("iptables -I OUTPUT -p icmp --icmp-type destination-unreachable -j DROP")

    # no need for promiscuous mode
    #conf.sniff_promisc = 0

    t_end = time.time() + args.time
    while time.time() < t_end:
        for sport1 in range(args.src_port, args.src_port+src_port_count):
            send(IP(src=args.src_ip, dst=args.dst_ip)/
                    UDP(sport=sport1, dport=args.dst_port)/
                        "CCCCCCCCCCCCCCCCCCCCCCCCCCCC", verbose=0,
                        count=packet_count, inter=0.01, iface=args.dev)
            sys.stdout.write('.'*packet_count)
            sys.stdout.flush()
        time.sleep(1)
    print


def run():
    args = parse_args()

    if args.l:
        run_listener(args)
    else:
        run_client(args)


if __name__ == '__main__':
    run()
