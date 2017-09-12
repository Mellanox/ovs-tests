#!/usr/bin/python

import os
import sys
import argparse
import subprocess
from glob import glob

MYNAME = os.path.basename(__file__)
MYDIR = os.path.abspath(os.path.dirname(__file__))

TESTS = sorted(glob(MYDIR + '/test-*'))
IGNORE_TESTS = [MYNAME]
SKIP_TESTS = {
    "test-eswitch-add-del-flows-during-flows-cleanup.sh": "RM #1013092",
    "test-eswitch-no-carrier.sh": "RM #1124753",
    "test-ovs-vxlan-in-ns-hw.sh": "Not a valid test?",
}

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
    def __init__(self, cmd, rc, stdout, stderr):
        self._cmd = cmd
        self._rc = rc
        self._stdout = stdout
        self._stderr = stderr

    def __str__(self):
        retval = " (exited with %d)" % self._rc
        stderr = " [%s]" % self._stderr
        return "Command execution failed%s%s" % (retval, stderr)


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


def run(cmd):
    subp = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, close_fds=True)
    (data_stdout, data_stderr) = subp.communicate()
    if subp.returncode:
        err = ExecCmdFailed(cmd, subp.returncode, data_stdout, data_stderr)
        raise err

    return (data_stdout, data_stderr)


def deco(line, color):
    return "\033[%dm%s\033[0m" % (COLOURS[color], line)


class TestResult(object):
    def __init__(self, name, res, out=''):
        self._name = name
        self._res = res
        self._out = out

    def __str__(self):
        res_color = {
            'SKIP': 'yellow',
            'OK': 'green',
            'DRY': 'yellow',
            'FAILED': 'red',
        }
        color = res_color.get(self._res, 'red')
        res = deco(self._res, color)
        name = deco(self._name, 'blue')
        ret = "Test: %-60s  %s" % (name, res)
        if self._out:
            out = self._out
            if self._res == 'SKIP':
                out = ' (%s)' % out
            else:
                out = '\n%s' % out
            ret += deco(out, color)
        return ret


def glob_tests(args, tests):
    if not args.glob:
        return
    from fnmatch import fnmatch
    for test in tests[:]:
        name = os.path.basename(test)
        if not fnmatch(name, args.glob):
            tests.remove(test)


def main():
    args = parse_args()
    ignore = False
    if args.from_test:
        ignore = True
    if args.exclude:
        IGNORE_TESTS.extend(args.exclude)
    glob_tests(args, TESTS)

    tests_results = []
    for test in TESTS:
        name = os.path.basename(test)
        if name in IGNORE_TESTS:
            continue
        if ignore:
            if args.from_test != name:
                continue
            ignore = False
        print "Execute test: %s" % name
        failed = False
        res = 'OK'
        out = ''
        if args.dry:
            res = 'DRY'
        elif name in SKIP_TESTS:
            res = 'SKIP'
            out = SKIP_TESTS[name]
        else:
            try:
                cmd = test
                if args.parm:
                    cmd += ' ' + args.parm
                run(cmd)
            except ExecCmdFailed, e:
                failed = True
                res = 'FAILED'
                out = str(e)

        print TestResult(name, res, out)
        if args.stop and failed:
            sys.exit(1)


if __name__ == "__main__":
    main()
