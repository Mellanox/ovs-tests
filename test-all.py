#!/usr/bin/python

import os
import re
import sys
import argparse
import subprocess
import yaml
from fnmatch import fnmatch
from glob import glob
from tempfile import mkdtemp
from mlxredmine import MlxRedmine
from datetime import datetime

MYNAME = os.path.basename(__file__)
MYDIR = os.path.abspath(os.path.dirname(__file__))
LOGDIR = ''
TESTS = glob(MYDIR + '/test-*')
IGNORE_TESTS = []
SKIP_TESTS = {}
SKIP_NOT_IN_DB = []
TESTS_SUMMARY = []

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
    global LOGDIR
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
                        help='exclude tests')
    parser.add_argument('--glob', '-g', action='append',
                        help='glob of tests')
    parser.add_argument('--db',
                        help='DB file to read for tests to run')
    parser.add_argument('--log_dir',
                        help='Log dir to save all logs under')
    parser.add_argument('--html', action='store_true',
                        help='Save log files in HTML and a summary')
    args = parser.parse_args()

    if args.log_dir:
        LOGDIR = args.log_dir
        os.mkdir(LOGDIR)
    else:
        LOGDIR = mkdtemp(prefix='log')
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


def deco(line, color, html=False):
    if html:
        return "<span style='color: %s'>%s</span>" % (color, line)
    else:
        return "\033[%dm%s\033[0m" % (COLOURS[color], line)


def strip_color(line):
    return re.sub(r"\033\[[0-9 ;]*m", '', line)


def format_result(res, out='', html=False):
    res_color = {
        'SKIP': 'yellow',
        'TEST PASSED': 'green',
        'OK': 'green',
        'DRY': 'yellow',
        'FAILED': 'red',
        'TERMINATED': 'red',
        'IGNORED': 'yellow',
    }
    color = res_color.get(res, 'yellow')
    if out:
        if res == 'SKIP':
            res += ' (%s)' % out
        else:
            res += ' %s' % out
    return deco(res, color, html)


def sort_tests(tests):
    tests.sort(key=lambda x: os.path.basename(x).split('.')[0])


def glob_tests(args, tests):
    if not args.glob:
        return
    _tests = []

    if len(args.glob) == 1 and (' ' in args.glob[0] or '\n' in args.glob[0]):
        args.glob = args.glob[0].strip().split()

    if len(args.glob) == 1 and ',' in args.glob[0]:
        args.glob = args.glob[0].split(',')

    for test in tests[:]:
        name = os.path.basename(test)
        for g in args.glob:
            if fnmatch(name, g):
                _tests.append(test)
                break
    for test in tests[:]:
        if test not in _tests:
            tests.remove(test)


def update_skip_according_to_db(db_file):
    global SKIP_TESTS, SKIP_NOT_IN_DB
    data = {}
    print "Reading DB: %s" % db_file
    with open(db_file) as yaml_data:
        data = yaml.safe_load(yaml_data)
    print "Description: %s" % data.get("description", "DB doesn't include a description")
    rm = MlxRedmine()
    test_will_run = False
    for t in TESTS:
        t = os.path.basename(t)
        if t not in data['tests']:
            SKIP_NOT_IN_DB.append(t)
            continue
        if data['tests'][t] is None:
            data['tests'][t] = {}
        bugs_list = []
        for kernel in data['tests'][t].get('ignore_kernel', {}):
            if re.search("^%s$" % kernel, os.uname()[2]):
                for bug in data['tests'][t]['ignore_kernel'][kernel]:
                    bugs_list.append(bug)

        for bug in bugs_list:
            task = rm.get_issue(bug)
            if rm.is_issue_open(task):
                SKIP_TESTS[t] = "RM #%s: %s" % (bug, task['subject'])
            sys.stdout.write('.')
            sys.stdout.flush()

        if t not in SKIP_TESTS:
            test_will_run = True
    print

    if not test_will_run:
        raise Exception('All Tests will be ignored !')


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
        bugs = re.findall(r"#\s*Bug SW #([0-9]+):", data)
        for b in bugs:
            task = rm.get_issue(b)
            if rm.is_issue_open(task):
                SKIP_TESTS[t] = "RM #%s: %s" % (b, task['subject'])
            sys.stdout.write('.')
            sys.stdout.flush()

        if t not in SKIP_TESTS and 'IGNORE_FROM_TEST_ALL' in data:
            SKIP_TESTS[t] = "IGNORE_FROM_TEST_ALL"
    print


def should_ignore_test(name, exclude):
    if name in exclude or name in ' '.join(exclude):
        return True

    for x in exclude:
        if fnmatch(name, x):
            return True

    return False


def save_summary_html():
    html = """<!DOCTYPE html>
<html>
    <head>
        <title>Summary</title>
    </head>
    <body>
        <table>
            <tr>
                <th bgcolor='grey' align='left'>Test</th>
                <th bgcolor='grey' align='left'>Time</th>
                <th bgcolor='grey' align='left'>Status</th>
            </tr>"""

    for t in TESTS_SUMMARY:
        status = t['status']
        if t.get('test_log', ''):
            status = ("<a href='{test_log}'>{status}</a>".format(
                test_log=t['test_log'],
                status=status))
        html += """
            <tr>
                <td bgcolor='lightgray' align='left'><b>{test}</b></td>
                <td bgcolor='lightgray' align='left'>{run_time}</td>
                <td bgcolor='lightgray' align='left'>{status}</td>
            </tr>""" .format(test=t['test_name'],
                             run_time=t['run_time'],
                             status=status)
    html += """
        </table>
    </body>
</html>"""

    summary_file = "%s/summary.html" % LOGDIR
    with open(summary_file, 'w') as f:
        f.write(html)
        f.close()

    print "Summary: %s" % summary_file


def main(args):
    global TESTS_SUMMARY
    exclude = []
    ignore = False

    if args.from_test:
        ignore = True

    if args.exclude:
        exclude.extend(args.exclude)

    exclude.extend(IGNORE_TESTS)
    glob_tests(args, TESTS)
    sort_tests(TESTS)

    print "Log dir: " + LOGDIR
    try:
        if args.db:
            update_skip_according_to_db(args.db)
        else:
            update_skip_according_to_rm()
    except KeyboardInterrupt:
        print 'Interrupted'
        return 1

    print "%-54s %-8s %s" % ("Test", "Time", "Status")
    tests_results = []
    failed = False
    terminated = False
    for test in TESTS:
        name = os.path.basename(test)
        if name == MYNAME:
            continue
        if name in SKIP_NOT_IN_DB:
            continue
        if ignore:
            if args.from_test != name:
                continue
            ignore = False

        print "%-62s " % deco(name, 'light-blue'),
        test_summary = {'test_name': name,
                        'test_log':  '',
                        'run_time':  '0.0',
                        'status':    'UNKNOWN',
                        }
        sys.stdout.flush()

        res = 'OK'
        skip_reason = ''
        out = ''

        start_time = datetime.now()
        if should_ignore_test(name, exclude):
            res = 'IGNORED'
        elif name in SKIP_TESTS:
            res = 'SKIP'
            skip_reason = SKIP_TESTS[name]
        elif args.dry:
            res = 'DRY'
        else:
            try:
                test_summary['test_log'] = '%s.log' % name
                cmd = test
                res = run_test(cmd)
            except ExecCmdFailed, e:
                failed = True
                res = 'FAILED'
                out = str(e)
            except KeyboardInterrupt:
                terminated = True
                res = 'TERMINATED'

        end_time = datetime.now()
        total_seconds = "%-7.2f" % (end_time-start_time).total_seconds()
        test_summary['run_time'] = total_seconds
        print "%s " % total_seconds,

        test_summary['status'] = format_result(res, skip_reason, html=True)
        print "%-60s" % format_result(res, skip_reason + out)

        TESTS_SUMMARY.append(test_summary)

        if (args.stop and failed) or terminated:
            return 1
    # end test loop

    return failed


if __name__ == "__main__":
    args = parse_args()
    rc = main(args)
    if args.html:
        save_summary_html()
    sys.exit(rc)
