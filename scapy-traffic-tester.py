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
                        help='Source port count. helper to get more streams.')
    parser.add_argument('--dst-port', type=int, default=3000,
                        help='Destination port')
    parser.add_argument('--dst-port-count', type=int, default=1,
                        help='Destination port count. helper to get more streams.')
    parser.add_argument('--pkt-count', type=int, default=10,
                        help='Packet count')
    parser.add_argument('--inter', type=float, default=0.05,
                        help='Interval between send')
    parser.add_argument('--time', type=int, default=10,
                        help='Time in seconds to run client. Issue packet count per second.')

    args = parser.parse_args()
    return args


def verify_args(args, needed):
    err = False
    for i in needed:
        v = getattr(args, i)
        if v is None:
            v = '(Missing)'
            err = True
        print '%s: %s' % (i, v)

    if err:
        sys.exit(1)


def run_listener(args):
    print "Run as listener"

    needed = ('dev', 'src_ip', 'time')
    verify_args(args, needed)

    ifname = args.dev
    src_ip = args.src_ip

    # ignore icmp unreachable packets
    os.system("iptables -I OUTPUT -p icmp --icmp-type destination-unreachable -j DROP")

    global _c, st
    _c = 0
    st = time.time()

    def custom_action(sock):

        def packet_fwd(pkt):
            global _c, st
            _c+=1
            pkt = (IP(dst=pkt[IP].src, src=pkt[IP].dst)/
                    UDP(dport=pkt[UDP].sport, sport=pkt[UDP].dport)/
                    "BBBBBBBBBBBBBBBBBBBBBBBBBBBB")
            send(pkt, verbose=0, iface=ifname, socket=sock)
            now = time.time()
            if now - st > 1:
                st = now
                sys.stdout.write(',received %s packets,' % _c)
                sys.stdout.flush()

        return packet_fwd

    filter1 = "udp and src host %s" % src_ip
    print "Start sniff and fwd on %s" % ifname
    print "filter: %s" % filter1
    sock = conf.L3socket(iface=args.dev)
    try:
        x = sniff(iface=ifname, prn=custom_action(sock), filter=filter1, timeout=args.time)
    finally:
        sock.close()
    print
    print 'received %s packets' % len(x)


def run_client(args):
    print "Run as client"

    needed = ('dev', 'src_ip', 'dst_ip', 'src_port', 'src_port_count',
              'dst_port', 'dst_port_count', 'pkt_count', 'inter', 'time')
    verify_args(args, needed)

    packet_count = args.pkt_count

    # ignore icmp unreachable packets
    os.system("iptables -I OUTPUT -p icmp --icmp-type destination-unreachable -j DROP")

    # no need for promiscuous mode
    #conf.sniff_promisc = 0

    sent = 0
    t_end = time.time() + args.time
    pkt_list = []

    for sport1 in range(args.src_port, args.src_port + args.src_port_count):
        for dport1 in range(args.dst_port, args.dst_port + args.dst_port_count):
            pkt = (IP(src=args.src_ip, dst=args.dst_ip)/
                    UDP(sport=sport1, dport=dport1)/
                    "CCCCCCCCCCCCCCCCCCCCCCCCCCCC")
            pkt_list.append(pkt)

    print "Generated %d packets" % len(pkt_list)
    s = conf.L3socket(iface=args.dev)
    try:
        while time.time() < t_end:
            for pkt in pkt_list:
                send(pkt, verbose=0, count=packet_count, inter=args.inter, iface=args.dev, socket=s)
                sent += packet_count
                if sent % 100 == 0:
                    sys.stdout.write('.')
                    sys.stdout.flush()
    finally:
        s.close()
    print
    print "sent %d packets" % sent


def run():
    args = parse_args()

    if args.l:
        run_listener(args)
    else:
        run_client(args)


if __name__ == '__main__':
    run()
