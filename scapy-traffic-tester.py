#!/usr/bin/python

import os
import sys
import argparse
import time
import random
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
    parser.add_argument('--src-port', type=int, default=0,
                        help='Source port')
    parser.add_argument('--src-port-count', type=int, default=1,
                        help='Source port count. helper to get more streams.')
    parser.add_argument('--dst-port', type=int, default=0,
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
    print "---- Run as listener ----"

    needed = ('dev', 'src_ip', 'time')
    verify_args(args, needed)

    ifname = args.dev
    src_ip = args.src_ip

    # ignore icmp unreachable packets
    #os.system("iptables -I OUTPUT -p icmp --icmp-type destination-unreachable -j DROP")

    global _c
    _c = 0

    global payload
    data = 'Z'
    data_size = 1024
    payload = data*data_size

    def custom_action(sock):

        def packet_fwd(pkt):
            global _c, payload
            _c+=1
            pkt = (IP(dst=pkt[IP].src, src=pkt[IP].dst)/
                    UDP(dport=pkt[UDP].sport, sport=pkt[UDP].dport)/
                    payload)
            send(pkt, verbose=0, iface=ifname, socket=sock)
            if _c % 500 == 0:
                sys.stdout.write(',')
                sys.stdout.flush()

        return packet_fwd

    filter1 = "udp and src host %s" % src_ip
    print "Start sniff and fwd on %s" % ifname
    print "filter: %s" % filter1
    sock = conf.L3socket(iface=args.dev)
    try:
        x = sniff(iface=ifname, prn=custom_action(sock), filter=filter1, timeout=args.time, store=0)
    finally:
        sock.close()

    print
    print 'received %s packets' % _c


def run_client(args):
    print "---- Run as client ----"

    if not args.src_port:
        args.src_port = random.randrange(1026, 1999)
    if not args.dst_port:
        args.dst_port = random.randrange(2026, 2999)

    needed = ('dev', 'src_ip', 'dst_ip', 'src_port', 'src_port_count',
              'dst_port', 'dst_port_count', 'pkt_count', 'inter', 'time')
    verify_args(args, needed)

    # ignore icmp unreachable packets
    #os.system("iptables -I OUTPUT -p icmp --icmp-type destination-unreachable -j DROP")

    # no need for promiscuous mode
    #conf.sniff_promisc = 0

    sent = 0
    pkt_list = []

    data = 'Z'
    data_size = 1024
    payload = data*data_size

    for sport1 in range(args.src_port, args.src_port + args.src_port_count):
        for dport1 in range(args.dst_port, args.dst_port + args.dst_port_count):
            pkt = (IP(src=args.src_ip, dst=args.dst_ip)/
                    UDP(sport=sport1, dport=dport1)/
                    payload)
            pkt_list.append(pkt)

    print "Prepared %d packets" % len(pkt_list)
    t_end = time.time() + args.time
    s = conf.L3socket(iface=args.dev)
    progress = random.choice(['.', ',', 'a', 'b', 'c', 'z'])
    try:
        while time.time() < t_end:
            for pkt in pkt_list:
                send(pkt, verbose=0, count=args.pkt_count, inter=args.inter, iface=args.dev, socket=s)
                sent += args.pkt_count
                if sent % 500 == 0:
                    sys.stdout.write(progress)
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
