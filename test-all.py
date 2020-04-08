#!/usr/bin/python

import os
import re
import sys
import argparse
import subprocess
import yaml
import random
import traceback
import signal
from ansi2html import Ansi2HTMLConverter
from fnmatch import fnmatch
from glob import glob
from tempfile import mkdtemp
from mlxredmine import MlxRedmine
from datetime import datetime

# HTML components
SUMMARY_ROW = """<tr>
    <td bgcolor='lightgray' align='left'><b>{number_of_tests}</b></td>
    <td bgcolor='lightgray' align='left'><b>{passed_tests}</b></td>
    <td bgcolor='lightgray' align='left'><b>{failed_tests}</b></td>
    <td bgcolor='lightgray' align='left'><b>{skip_tests}</b></td>
    <td bgcolor='lightgray' align='left'><b>{ignored_tests}</b></td>
    <td bgcolor='lightgray' align='left'><b>{pass_rate}</b></td>
                </tr>"""
RESULT_ROW = """<tr>
    <td bgcolor='lightgray' align='left'><b>{test}</b></td>
    <td bgcolor='lightgray' align='left'>{run_time}</td>
    <td bgcolor='lightgray' align='left'>{status}</td>
                </tr>"""
HTML = """
<!DOCTYPE html>
<html>
    <head>
        <title>Summary</title>
    </head>
    <body>
        <table>
            <thead>
                <tr>
                    <th bgcolor='grey' align='left'>Number of tests</th>
                    <th bgcolor='grey' align='left'>Number of passed tests</th>
                    <th bgcolor='grey' align='left'>Number of failed tests</th>
                    <th bgcolor='grey' align='left'>Number of skipped tests</th>
                    <th bgcolor='grey' align='left'>Number of ignored tests</th>
                    <th bgcolor='grey' align='left'>Passrate</th>
                </tr>
            </thead>
            <tbody>
                {summary}
            </tbody>
        </table>
        <br>
        <table>
            <thead>
                 <tr>
                    <th bgcolor='grey' align='left'>Test</th>
                    <th bgcolor='grey' align='left'>Time</th>
                    <th bgcolor='grey' align='left'>Status</th>
                 </tr>
            </thead>
            <tbody>
                {results}
            </tbody>
        </table>
    </body>
</html>
"""

MYNAME = os.path.basename(__file__)
MYDIR = os.path.abspath(os.path.dirname(__file__))
LOGDIR = ''
TESTS = []
IGNORE_TESTS = []
SKIP_TESTS = {}
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
    parser.add_argument('--randomize', '-r', default=False,
                        help='Randomize the order of the tests',
                        action='store_true')

    return parser.parse_args()


def run_test(cmd, html=False):
    logname = os.path.join(LOGDIR, os.path.basename(cmd))
    # piping stdout to file seems to miss stderr msgs to we use pipe
    # and write to file at the end.
    subp = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, close_fds=True)
    out = subp.communicate()
    log = out[0]

    with open("%s.log" % logname, 'w') as f1:
        f1.write(log)

    if html:
        with open("%s.html" % logname, 'w') as f2:
            f2.write(Ansi2HTMLConverter().convert(log))

    status = log.splitlines()[-1].strip()
    status = strip_color(status)

    if subp.returncode:
        status = "(%s) %s" % (status, logname + ".log")
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


def sort_tests(args, tests):
    if args.randomize:
        print 'Randomizing the tests order'
        random.shuffle(tests)
    else:
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


def get_current_fw():
    if "CONFIG" not in os.environ:
        print "ERROR: Cannot ignore by FW because CONFIG environment variable is missing."
        return None

    config = os.environ.get('CONFIG')
    try:
        with open(config, 'r') as f1:
            for line in f1.readlines():
                if "NIC=" in line:
                    interface = line.split("NIC=")[1].strip()
    except IOError:
        print "ERROR: Cannot read config %s" % config
        return None

    if not interface:
        print "ERROR: Cannot find NIC in CONFIG."
        return None

    fw = subprocess.check_output("ethtool -i enp0s8f0 | grep firmware-version | awk {'print $2'}", shell=True).strip()
    return fw


def update_skip_according_to_db(data):
    global SKIP_TESTS

    rm = MlxRedmine()
    test_will_run = False
    current_fw_ver = get_current_fw()

    for t in TESTS:
        t = os.path.basename(t)
        if data['tests'][t] is None:
            data['tests'][t] = {}

        bugs_list = []
        for kernel in data['tests'][t].get('ignore_kernel', {}):
            if re.search("^%s$" % kernel, os.uname()[2]):
                for bug in data['tests'][t]['ignore_kernel'][kernel]:
                    bugs_list.append(bug)

        for fw in data['tests'][t].get('ignore_fw', {}):
            if re.search("^%s$" % fw, current_fw_ver):
                for bug in data['tests'][t]['ignore_fw'][fw]:
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
    number_of_tests = len(TESTS)
    passed_tests = sum(map(lambda test: 'TEST PASSED' in test['status'], TESTS_SUMMARY))
    failed_tests = sum(map(lambda test: 'FAILED' in test['status'], TESTS_SUMMARY))
    skip_tests = sum(map(lambda test: 'SKIP' in test['status'], TESTS_SUMMARY))
    ignored_tests = sum(map(lambda test: 'IGNORED' in test['status'], TESTS_SUMMARY))
    pass_rate = str(int(passed_tests / float(number_of_tests - skip_tests - ignored_tests) * 100)) + '%'

    summary = SUMMARY_ROW.format(number_of_tests=number_of_tests, passed_tests=passed_tests,
                                 failed_tests=failed_tests,
                                 skip_tests=skip_tests, ignored_tests=ignored_tests, pass_rate=pass_rate)
    results = ''
    for t in TESTS_SUMMARY:
        status = t['status']
        if t.get('test_log', ''):
            status = ("<a href='{test_log}'>{status}</a>".format(
                test_log=t['test_log'],
                status=status))
        results += RESULT_ROW.format(test=t['test_name'],
                                     run_time=t['run_time'],
                                     status=status)

    running_tests_names = [t['test_name'] for t in TESTS_SUMMARY]

    for t in TESTS:
        t = os.path.basename(t)
        if t not in running_tests_names:
            status = deco("DID'T RUN", 'darkred', html=True)
            results += RESULT_ROW.format(
                test=t,
                run_time=0.0,
                status=status)

    summary_file = "%s/summary.html" % LOGDIR
    with open(summary_file, 'w') as f:
        f.write(HTML.format(summary=summary, results=results))
        f.close()

    print "Summary: %s" % summary_file


def prepare_logdir():
    global LOGDIR
    if not args.dry:
        if args.log_dir:
            LOGDIR = args.log_dir
            os.mkdir(LOGDIR)
        else:
            LOGDIR = mkdtemp(prefix='log')
        print "Log dir: " + LOGDIR


def read_db():
    print "Reading DB: %s" % args.db
    with open(args.db) as yaml_data:
        data = yaml.safe_load(yaml_data)
        print "Description: %s" % data.get("description", "DB doesn't include a description")
        return data


def load_tests_from_db(data):
    return [MYDIR + '/' + key for key in data['tests']]


def get_tests():
    global TESTS
    try:
        if args.db:
            data = read_db()
            TESTS = load_tests_from_db(data)
            update_skip_according_to_db(data)
        else:
            TESTS = glob(MYDIR + '/test-*')
            glob_tests(args, TESTS)
            update_skip_according_to_rm()

        return 0
    except RuntimeError, e:
        print "ERROR: %s" % e
        return 1


def main(args):
    global TESTS_SUMMARY
    exclude = []
    ignore = False

    rc = get_tests()

    if rc != 0:
        return 1

    if len(TESTS) == 0:
        print "ERROR: No tests to run"
        return 1

    if args.from_test:
        ignore = True

    if args.exclude:
        exclude.extend(args.exclude)

    exclude.extend(IGNORE_TESTS)
    sort_tests(args, TESTS)

    print "%-54s %-8s %s" % ("Test", "Time", "Status")
    tests_results = []
    failed = False

    for test in TESTS:
        name = os.path.basename(test)
        if name == MYNAME:
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
                test_summary['test_log'] = '%s.html' % name
                cmd = test
                res = run_test(cmd, args.html)
            except ExecCmdFailed, e:
                failed = True
                res = 'FAILED'
                out = str(e)

        end_time = datetime.now()
        total_seconds = "%-7.2f" % (end_time - start_time).total_seconds()
        test_summary['run_time'] = total_seconds
        print "%s " % total_seconds,

        test_summary['status'] = format_result(res, skip_reason, html=True)
        print "%-60s" % format_result(res, skip_reason + out)

        TESTS_SUMMARY.append(test_summary)

        if args.stop and failed:
            return 1
    # end test loop

    return failed


def signal_handler(signum, frame):
    print "\nterminated"
    if args.html and not args.dry:
        print "Saving results..."
        save_summary_html()
    sys.exit(signum)


if __name__ == "__main__":
    args = parse_args()
    prepare_logdir()
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    rc = main(args)
    if args.html and not args.dry:
        save_summary_html()
    sys.exit(rc)
