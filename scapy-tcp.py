#!/usr/bin/python

from __future__ import print_function

import argparse
import random
import os
import sys
from scapy.all import *


def send1(pkt):
    send(pkt)


def conn(ip1, sport, ip2, dport):
    dmac = "00:04:4b:e1:27:00"
    iface = "enp8s0f1v0"
    eth = Ether(dst=dmac)
    print("Connection %s:%s <-> %s:%s handshake" % (ip1, sport, ip2, dport))
    send1(eth/IP(src=ip1,dst=ip2)/TCP(sport=sport,dport=dport,seq=100,flags='S'))
    send1(eth/IP(src=ip2,dst=ip1)/TCP(sport=dport,dport=sport,seq=51,ack=101,flags='SA'))
    send1(eth/IP(src=ip1,dst=ip2)/TCP(sport=sport,dport=dport,seq=101,ack=52,flags='A'))
    print("Data out")
    send1(eth/IP(src=ip1,dst=ip2)/TCP(sport=sport,dport=dport,seq=101,ack=52,flags='A')/"A1")
    send1(eth/IP(src=ip1,dst=ip2)/TCP(sport=sport,dport=dport,seq=103,ack=52,flags='A')/"A2")
    send1(eth/IP(src=ip1,dst=ip2)/TCP(sport=sport,dport=dport,seq=105,ack=52,flags='A')/"A3")
    print("Data in")
    send1(eth/IP(src=ip2,dst=ip1)/TCP(sport=dport,dport=sport,seq=52,ack=107,flags='A')/"B1")
    send1(eth/IP(src=ip2,dst=ip1)/TCP(sport=dport,dport=sport,seq=54,ack=107,flags='A')/"B2")
    print("More random data out")
    #sendp(Ether(src='10:70:fd:47:3c:a8', dst='10:70:fd:2f:ee:c4')/eth/IP(src='45.0.0.1',dst='45.0.0.9')/TCP(sport=1001,dport=2001)/Raw(RandString(size=1008)), iface='enp130s0f0np0', count=200)
    sendp(eth/IP(src=ip1,dst=ip2)/TCP(sport=sport,dport=dport)/Raw(RandString(size=1008)), iface=iface, count=200)
    print("Teardown")
    send1(eth/IP(src=ip1,dst=ip2)/TCP(sport=sport,dport=dport,seq=107,ack=56,flags='FA'))
    send1(eth/IP(src=ip2,dst=ip1)/TCP(sport=dport,dport=sport,seq=56,ack=108,flags='FA'))
    send1(eth/IP(src=ip1,dst=ip2)/TCP(sport=sport,dport=dport,seq=108,ack=57,flags='A'))
    print("Connection %s:%s <-> %s:%s done" % (ip1, sport, ip2, dport))


def main():
    sport = random.randrange(1526, 60000)
    dport = random.randrange(1526, 60000)
    ip1 = '7.7.7.1'
    ip2 = '7.7.7.2'
    for i in range(10):
        conn(ip1, sport, ip2, dport)


if __name__ == "__main__":
    main()
