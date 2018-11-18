#!/usr/bin/python

import os
import re
import sys
import argparse
import subprocess
from fnmatch import fnmatch
from glob import glob
from tempfile import mkdtemp
from mlxredmine import MlxRedmine


MYNAME = os.path.basename(__file__)
MYDIR = os.path.abspath(os.path.dirname(__file__))
LOGDIR = mkdtemp(prefix='log')

TESTS = sorted(glob(MYDIR + '/test-*'))
IGNORE_TESTS = [MYNAME]
SKIP_TESTS = {}

COLOURS = {
    "black": 30,
    "red": 31,
    "green": 32,
    "yellow": 33,
    "blue": 34,
    "magenta": 25,
    "cyan": 36,
    "light-gray": 37,
    "dark-gray": 90,
    "light-red": 91,
    "light-green": 92,
    "light-yellow": 93,
    "light-blue": 94,
    "light-magenta": 95,
    "light-cyan": 96,
    "white": 97,
}


class ExecCmdFailed(Exception):
    def __init__(self, cmd, rc, logname):
        self._cmd = cmd
        self._rc = rc
        self._logname = logname

    def __str__(self):
        return self._logname


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='verbose output')
    parser.add_argument('--stop', '-s', action='store_true',
                        help='stop on first error')
    parser.add_argument('--dry', '-d', action='store_true',
                        help='not to actually run the test')
    parser.add_argument('--from_test', '-f',
                        help='start from test')
    parser.add_argument('--exclude', '-e', action='append',
                        help='exclude test')
    parser.add_argument('--glob', '-g',
                        help='glob of tests')
    parser.add_argument('--parm', '-p',
                        help='Pass parm to each test')

    args = parser.parse_args()
    return args


def run_test(cmd):
    logname = os.path.join(LOGDIR, os.path.basename(cmd)+'.log')
    with open(logname, 'w') as f1:
        # piping stdout to file seems to miss stderr msgs to we use pipe
        # and write to file at the end.
        subp = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, close_fds=True)
        out = subp.communicate()
        f1.write(out[0])

    status = out[0].splitlines()[-1].strip()
    status = strip_color(status)

    if subp.returncode:
        status = "(%s) %s" % (status, logname)
        raise ExecCmdFailed(cmd, subp.returncode, status)

    return status


def deco(line, color):
    return "\033[%dm%s\033[0m" % (COLOURS[color], line)


def strip_color(line):
    return re.sub("\033\[[0-9 ;]*m", '', line)


def print_result(res, out):
    res_color = {
        'SKIP': 'yellow',
        'TEST PASSED': 'green',
        'OK': 'green',
        'DRY': 'yellow',
        'FAILED': 'red',
        'IGNORED': 'yellow',
    }
    color = res_color.get(res, 'yellow')
    cres = deco(res, color)
    if out:
        if res == 'SKIP':
            out = ' (%s)' % out
        else:
            out = ' %s' % out
        cres += deco(out, color)
    print cres


def glob_tests(args, tests):
    if not args.glob:
        return
    for test in tests[:]:
        name = os.path.basename(test)
        if not fnmatch(name, args.glob):
            tests.remove(test)


def update_skip_according_to_rm():
    global SKIP_TESTS

    print "Check redmine for open issues"
    rm = MlxRedmine()
    SKIP_TESTS = {}
    for t in TESTS:
        data = []
        with open(t) as f:
            for line in f.xreadlines():
                if line.startswith('#') or not line.strip():
                    data.append(line)
                else:
                    break
        data = ''.join(data)
        t = os.path.basename(t)
        bugs = re.findall("#\s*Bug SW #([0-9]+):", data)
        for b in bugs:
            task = rm.get_issue(b)
            if rm.is_issue_open(task):
                SKIP_TESTS[t] = "RM #%s: %s" % (b, task['subject'])
            sys.stdout.write('.')
            sys.stdout.flush()

        if t not in SKIP_TESTS and 'IGNORE_FROM_TEST_ALL' in data:
            SKIP_TESTS[t] = "IGNORE_FROM_TEST_ALL"
    print


def should_ignore_test(name):
    if name in IGNORE_TESTS or name in ' '.join(IGNORE_TESTS):
        return True

    for x in IGNORE_TESTS:
        if fnmatch(name, x):
            return True

    return False


def main():
    args = parse_args()
    ignore = False
    if args.from_test:
        ignore = True
    if args.exclude:
        IGNORE_TESTS.extend(args.exclude)
    glob_tests(args, TESTS)

    print "Log dir: " + LOGDIR
    try:
        update_skip_according_to_rm()
    except KeyboardInterrupt:
        print 'Interrupted'
        sys.exit(1)

    tests_results = []
    for test in TESTS:
        name = os.path.basename(test)
        if name == MYNAME:
            continue
        if ignore:
            if args.from_test != name:
                continue
            ignore = False

        print "Test: %-60s  " % deco(name, 'light-blue'),
        sys.stdout.flush()

        failed = False
        res = 'OK'
        out = ''

        if should_ignore_test(name):
            res = 'IGNORED'
        elif name in SKIP_TESTS:
            res = 'SKIP'
            out = SKIP_TESTS[name]
        elif args.dry:
            res = 'DRY'
        else:
            try:
                cmd = test
                if args.parm:
                    cmd += ' ' + args.parm
                res = run_test(cmd)
            except ExecCmdFailed, e:
                failed = True
                res = 'FAILED'
                out = str(e)
            except KeyboardInterrupt:
                print 'Interrupted'
                sys.exit(1)

        print_result(res, out)

        if args.stop and failed:
            sys.exit(1)
    # end test loop


if __name__ == "__main__":
    main()
