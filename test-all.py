#!/usr/bin/python

import os
import re
import sys
import argparse
import tempfile
import subprocess
from glob import glob
from mlxredmine import MlxRedmine


MYNAME = os.path.basename(__file__)
MYDIR = os.path.abspath(os.path.dirname(__file__))
LOGDIR = tempfile.mkdtemp(prefix='log')

TESTS = sorted(glob(MYDIR + '/test-*'))
IGNORE_TESTS = [MYNAME]
SKIP_TESTS = {
    "test-eswitch-add-del-flows-during-flows-cleanup.sh": "RM #1013092",
    "test-eswitch-no-carrier.sh": "RM #1124753",
    "test-ovs-vxlan-in-ns-hw.sh": "Not a valid test?",
    "test-tc-replace.sh": "RM #988519",
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
    def __init__(self, cmd, rc, logname):
        self._cmd = cmd
        self._rc = rc
        self._logname = logname

    def __str__(self):
        retval = "(exited with %d)" % self._rc
        return "Command execution failed %s: %s" % (retval, self._logname)


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

    if subp.returncode:
        err = ExecCmdFailed(cmd, subp.returncode, logname)
        raise err

    return out


def deco(line, color):
    return "\033[%dm%s\033[0m" % (COLOURS[color], line)


class TestResult(object):
    def __init__(self, name, res, out=''):
        self._name = name
        self._res = res
        self._out = out

    def __result(self, summary=False):
        res_color = {
            'SKIP': 'yellow',
            'OK': 'green',
            'DRY': 'yellow',
            'FAILED': 'red',
            'IGNORED': 'yellow',
        }
        color = res_color.get(self._res, 'red')
        res = deco(self._res, color)
        name = deco(self._name, 'blue')
        ret = "Test: %-60s  %s" % (name, res)
        if self._out:
            out = self._out
            if self._res == 'SKIP':
                out = ' (%s)' % out
            elif not summary:
                out = '\n%s' % out
            else:
                out = ''
            ret += deco(out, color)
        return ret

    def __str__(self):
        return self.__result()

    @property
    def summary_result(self):
        return self.__result(summary=True)


def glob_tests(args, tests):
    if not args.glob:
        return
    from fnmatch import fnmatch
    for test in tests[:]:
        name = os.path.basename(test)
        if not fnmatch(name, args.glob):
            tests.remove(test)


def update_skip_according_to_rm():
    global SKIP_TESTS

    print "Check redmine status for open issues"
    rm = MlxRedmine()
    SKIP_TESTS = {}
    for t in TESTS:
        with open(t) as f:
            data = f.read()
        t = os.path.basename(t)
        bugs = re.findall("Bug SW #([0-9]+):", data)
        for b in bugs:
            task = rm.get_issue(b)
            if rm.is_issue_open(task):
                SKIP_TESTS[t] = "RM #%s: %s" % (b, task['subject'])
            print '.',
            sys.stdout.flush()
    print


def should_ignore_test(name):
    if name in IGNORE_TESTS or name in ' '.join(IGNORE_TESTS):
        return True
    else:
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
    update_skip_according_to_rm()

    tests_results = []
    for test in TESTS:
        name = os.path.basename(test)
        if ignore:
            if args.from_test != name:
                continue
            ignore = False

        print "Execute test: %s" % name
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
                run_test(cmd)
            except ExecCmdFailed, e:
                failed = True
                res = 'FAILED'
                out = str(e)

        tr = TestResult(name, res, out)
        print tr
        tests_results.append(tr)
        if args.stop and failed:
            sys.exit(1)

    print "Summary"
    for tr in tests_results:
        print tr.summary_result


if __name__ == "__main__":
    main()
