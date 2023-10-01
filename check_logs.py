#!/usr/bin/python

import argparse
import requests
from glob import glob
import os
import re


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', required=True, help='Results url')

    return parser.parse_args()


TAGS_ON_SUCCESS = [
    'error',
    'failed',
    'mlx5_cmd_out_err',
    'unreferenced object',
    'backtrace',
    'invalid handle',
    'WARNING',
    'Killed',
    'File exists',
    'SSH connection',
    'Cannot find device',
]

TAGS_ALWAYS = [
    'XXX',
    'TODO',
    'command not found',
    'No such file or directory',
]

expected = {
    'all': [
        'failed to flow_del'
    ],
    'test-eswitch-devlink-reload.sh': ['Warning: mlx5_core: reload while VFs are present is unfavorable.'],
    'test-ovs-dpdk-esw-mgr-removal.sh': ['Resource temporarily unavailable'],
    'test-ovs-dpdk-init-order.sh': [
        'ovs-vsctl: Error detected while setting up',
        'Resource temporarily unavailable'
    ]
}


def expected_line(test, line):
    _exp = expected['all'][:]
    _exp.extend(expected.get(test, []))
    for e in _exp:
        if e in line:
            return True
    return False


def start():
    tests = glob(os.path.join('*', "test-*.sh"))
    for test in tests:
        test = os.path.basename(test)
        if 'artifact/test_logs' in args.url:
            url = args.url + '/' + test + '.html'
        else:
            url = args.url + '/artifact/test_logs/' + test + '.html'
        r = requests.get(url)
        if not r.ok:
            # Didn't get the test names from summary so don't show an error.
            #print("SKIP: Failed to fetch url: %s" % r.status_code)
            continue

        _tags = TAGS_ALWAYS[:]
        if r.content.find('TEST PASSED') >= 0:
            _tags.extend(TAGS_ON_SUCCESS)

        br = False
        for i in _tags:
            for line in r.content.splitlines():
                if (i.lower() in line.lower()) and not expected_line(test, line):
                    break
            if i.lower() not in line.lower():
                continue
            print('%s - %s' % (test, i))
            print('    %s' % url)
            br = True
            break

        if br:
            continue

        for line in r.content.splitlines():
            m = re.search(r'.*\.sh: line .*: .*: .*', line)
            if m:
                print('%s - bash error: %s' % (test, m.group()))
                print('    %s' % url)


if __name__ == '__main__':
    args = parse_args()
    try:
        start()
    except KeyboardInterrupt:
        print("break")
