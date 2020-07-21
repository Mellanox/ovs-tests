#!/usr/bin/python
#
# The script converts tc cookie to ovs ufid.
#
# ./convert-ovs-ufid-to-tc-cookie.py [ufid]
#

from __future__ import print_function
import sys

if len(sys.argv) < 2:
    print("USAGE: Missing ufid argument")
    sys.exit(1)

ufid = sys.argv[1]

out = ""
word = []
try:
    sp = ufid.split('-')
    w3 = sp[4][:4]
    w4 = sp[3]
    w5 = sp[4][-8:]
    sp[3] = w3
    sp[4] = w4
    sp.append(w5)
except IndexError:
    print("ERROR: Invalid ufid?")
    sys.exit(1)

#replace w1 and w2
tmp = sp[1]
sp[1] = sp[2]
sp[2] = tmp

for i in sp:
        tmp=""
        for j in range(int(len(i)/2)):
                pos = j*2
                m = i[pos:pos+2]
                tmp = m+tmp
        word.append(tmp)

out = ''.join(word)

print(out)
