#!/usr/bin/python
#
# Compare usage slabinfo

import argparse
import sys
import re


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--slab-before', required=True)
    parser.add_argument('--slab-after', required=True)

    return parser.parse_args()


def read_slab(slab):
    with open(slab) as f:
        lines = f.readlines()

    b = {}
    for line in lines:
        line = line.strip()
        if line.startswith('#') or line.startswith('slabinfo'):
            continue
        p = line.split()
        key = p[0]
        b[key] = {
            'active_objs': int(p[1]),
            'num_objs': int(p[2]),
            'objsize': int(p[3]),
        }

    return b


def convert_unit(size):
    """ Convert the size from bytes to other units like KB, MB or GB"""

    if size > 1024*1024*1024:
        return "{:.2f} GB".format(size/(1024*1024*1024))
    elif size > 1024*1024:
        return "{:.2f} MB".format(size/(1024*1024))
    elif size > 1024:
        return "{:.2f} KB".format(size/(1024))
    else:
        return str(size)+" Bytes"



def main():
    args = parse_args()

    before = read_slab(args.slab_before)
    after = read_slab(args.slab_after)

    total_size = 0
    for key in before.keys():
        if (re.match("kmalloc-[0-9]+", key) or
            '0000:08:00' in key or
            key == 'nf_conntrack'):
            count = after[key]['active_objs'] - before[key]['active_objs']
            if (count < 1):
                continue
            size = count * after[key]['objsize']
            print(key, "\t", convert_unit(size))
            total_size += size

    print("total \t ", convert_unit(total_size))

    return 0


if __name__ == "__main__":
    sys.exit(main())
