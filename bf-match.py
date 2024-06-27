#!/usr/bin/env python3
#
# Print nic information related to VFs, SFs, HPFs for BF nic.
# The script needs to run on both host and BF arm imachines with
# the same data file to append and parse data from both machines.
#
# Example output:
#
# p0 b83f:d203:00c4:6330
#  VF   pf0vf0       -> REP pf0vf0
#  VF   pf0vf1       -> REP pf0vf1
#  VF   pf0vf2       -> REP pf0vf2
#  SF   pf0dpu1      -> REP pf0dpu1_r
#  SF   pf0dpu3      -> REP pf0dpu3_r
#                    -> HPF pf0hpf
# p1 b83f:d203:00c4:6331
#                    -> HPF pf1hpf

import os
import re
import sys
import yaml
import argparse
import netifaces
from glob import glob
from pprint import pprint

MYNAME = os.path.basename(__file__)
MYDIR = os.path.abspath(os.path.dirname(__file__))

DATA_FILE = os.path.join(MYDIR, 'data.yaml')
DATA = {}


def save():
    with open(DATA_FILE, 'w') as f:
        yaml.dump(DATA, f)


def load():
    global DATA
    if os.path.exists(DATA_FILE):
        with open(DATA_FILE) as f:
            DATA = yaml.safe_load(f)


def read_attr(nic, attr):
    try:
        for g in glob('/sys/class/net/%s/%s' % (nic, attr)):
            with open(g) as f:
                return f.read().strip()
    except OSError:
        return ''


def read_link(nic, link):
    try:
        return os.path.basename(os.readlink('/sys/class/net/%s/%s' % (nic, link)))
    except OSError:
        return ''


def node_guid_to_phys_id(guid):
    guid = "".join(guid.split(':'))
    guid = "".join(reversed([guid[i:i+2] for i in range(0, len(guid), 2)]))
    return guid


def get_virtfns(nic):
    virtfns = {}
    for virtfn in glob('/sys/class/net/%s/device/virtfn*' % nic):
        attr = os.path.basename(virtfn)
        val = read_link(nic, 'device/%s' % attr)
        if val:
            virtfns[attr] = val
    return virtfns


def read_nics():
    global DATA
    for iface in netifaces.interfaces():
        nic = {}

        for attr in ['phys_port_name', 'phys_switch_id', 'vendor',
                     'address', 'ifindex',
                     'device/infiniband/*/node_guid',
                     'device/infiniband/*/sys_image_guid',
                     'device/sfnum']:
            val = read_attr(iface, attr)
            if val:
                nic[os.path.basename(attr)] = val

        virtfns = get_virtfns(iface)
        if virtfns:
            nic['virtfns'] = virtfns

        for attr in ['device', 'device/driver', 'device/physfn']:
            val = read_link(iface, attr)
            if val:
                nic[os.path.basename(attr)] = val

        if os.path.exists('/sys/class/net/%s/rep_config' % iface):
            nic['is_representor'] = True

        if nic.get('physfn'):
            nic['is_vf'] = True
            val = read_attr(iface, 'device/physfn/infiniband/*/node_guid')
            if val:
                nic['parent_node_guid'] = val
                nic['parent_phys_switch_id'] = node_guid_to_phys_id(nic['parent_node_guid'])

        if nic.get('sys_image_guid') and not nic.get('phys_switch_id'):
            nic['phys_switch_id'] = node_guid_to_phys_id(nic['sys_image_guid'])

        nic['name'] = iface
        uniq = '%s-%s' % (nic['address'], nic['ifindex'])
        DATA[uniq] = nic


def is_parent(nic):
    if is_rep(nic) or not re.match(r'p(\d+)', nic.get('phys_port_name', '')):
        return False
    return True


def get_parent(nic):
    for key in DATA:
        p = DATA[key]
        if not is_parent(p):
            continue
        if p['phys_switch_id'] != nic['phys_switch_id']:
            continue
        m = re.search(r'pf?(\d+)', nic['phys_port_name'])
        if not m:
            continue
        pfnum = m.groups()[0]
        if p['phys_port_name'] != 'p'+pfnum:
            continue
        return p


def get_vf_parent(nic):
    for key in DATA:
        p = DATA[key]
        if not is_parent(p):
            continue
        if p['node_guid'] != nic['parent_node_guid']:
            continue
        return p


def get_nic(device):
    for key in DATA:
        nic = DATA[key]
        if nic.get('device') == device:
            return nic


def get_vf(rep, vfnum):
    p = get_parent(rep)
    if not p:
        return
    for vfn in p['virtfns']:
        vfn_ = re.match(r'virtfn(\d+)', vfn).groups()[0]
        if vfn_ != vfnum:
            continue
        virtfn = p['virtfns'][vfn]
        return get_nic(virtfn)


def get_sf(rep, sfnum):
    for key in DATA:
        sf = DATA[key]
        if sf.get('sfnum') != sfnum:
            continue
        return sf


def is_rep(nic):
    if not nic.get('is_representor') or not nic.get('device') or not nic.get('phys_switch_id'):
        return False
    return True


def is_vf(nic):
    if not nic.get('is_vf') or not nic.get('device') or not nic.get('parent_node_guid'):
        return False
    return True


def add_to_list(nic, key, new_item):
    lst = nic.get(key, [])
    subs = [sub['address'] for sub in lst]
    if new_item['address'] not in subs:
        lst += [new_item]
        nic[key] = lst


def link_reps():
    tree = {}
    for key in DATA:
        nic = DATA[key]
        parent = None

        if is_vf(nic):
            parent = get_vf_parent(nic)
            if parent:
                add_to_list(parent, 'vf', nic)
            continue
        elif not is_rep(nic):
            continue

        m = re.search(r'(pf?)(\d+)((vf|sf)(\d+))?', nic['phys_port_name'])
        if not m:
            continue

        if m.groups()[0] == 'p':
            nic_type = 'pf'
        else:
            nic_type = m.groups()[3]

        pf_num = m.groups()[1]
        num = m.groups()[4]

        if nic_type == 'pf':
            # pf rep
            parent = get_parent(nic)
            if parent:
                add_to_list(parent, 'pf-rep', nic)
        elif nic_type == 'vf':
            # vf rep
            vf = get_vf(nic, num)
            if vf:
                vf['rep_device'] = nic
                nic['vf_device'] = vf
        elif nic_type == 'sf':
            # sf rep
            sf = get_sf(nic, num)
            if sf:
                sf['rep_device'] = nic
                nic['sf_device'] = sf
                parent = get_parent(nic)
                if parent:
                    add_to_list(parent, 'sf', sf)
        elif not nic_type:
            # hpf
            parent = get_parent(nic)
            if parent:
                add_to_list(parent, 'hpf', nic)


def print_reps():
    for key in DATA:
        nic = DATA[key]
        if not is_parent(nic):
            continue
        print(nic['name'], nic['node_guid'])
        for vf in nic.get('vf', []):
            if vf.get('rep_device'):
                print(' %-4s %-12s' % ('VF', vf['name']), '-> REP', vf['rep_device']['name'])
        for sf in nic.get('sf', []):
            if sf.get('rep_device'):
                print(' %-4s %-12s' % ('SF', sf['name']), '-> REP', sf['rep_device']['name'])
        for hpf in nic.get('hpf', []):
            print(' %-17s -> HPF' % ' ', hpf['name'])
        for pf_rep in nic.get('pf-rep', []):
            print(' %-17s -> PF REP' % ' ', pf_rep['name'])


def parse_args():
    global DATA_FILE

    parser = argparse.ArgumentParser()
    parser.add_argument('--data-file',
                        help='data file. default: %s' % DATA_FILE)

    args = parser.parse_args()
    if args.data_file:
        DATA_FILE = os.path.abspath(args.data_file)

    if DATA_FILE.count('/') == 1 or len(DATA_FILE) < 5:
        print("ERROR: Invalid data file.")
        sys.exit(1)


def main():
    parse_args()
    load()
    read_nics()
    link_reps()
    print_reps()
    save()


if __name__ == "__main__":
    main()
