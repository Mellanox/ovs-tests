#!/usr/bin/python

# This script corrupt the sequence of a saved
# packet on a pcap file and send it on the requested interface

import sys
from scapy.all import *
from scapy.utils import rdpcap

pkts = rdpcap("/tmp/corruption-test-pkts.pcap")
for pkt in pkts:
    pkt['ESP'].seq = 222
    sendp(pkt, iface=sys.argv[1])  # sending packet at layer 2
