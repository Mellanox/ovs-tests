#!/usr/bin/python

from __future__ import print_function

import os
import re
import sys
import random
import signal
import argparse
import subprocess
from glob import glob
from fnmatch import fnmatch
from tempfile import mkdtemp
from datetime import datetime
from semver import VersionInfo

import yaml
from mlxredmine import MlxRedmine
from ansi2html import Ansi2HTMLConverter

# HTML components
SUMMARY_ROW = """
<tr>
    <td>{number_of_tests}</td>
    <td>{passed_tests}</td>
    <td>{failed_tests}</td>
    <td>{skip_tests}</td>
    <td>{ignored_tests}</td>
    <td>{pass_rate}</td>
    <td>{runtime}</td>
</tr>"""

RESULT_ROW = """
<tr>
    <td class="testname">{test}</td>
    <td>{run_time}</td>
    <td>{status}</td>
</tr>
"""

HTML_CSS = """
    <style>
      .asap_table td { background-color: lightgray; }
      .asap_table th { text-align: left; }
      .asap_table td.testname { font-weight: bold; }
      table#summary_table th { background-color: gray; }
      table#summary_table td { font-weight: bold; }
      table#results_table th { background-color: gray; }
    </style>
"""

HTML = """<!DOCTYPE html>
<html>
    <head>
        <title>Summary</title>
        {style}
    </head>
    <body>
        <table id="summary_table" class="asap_table">
            <thead>
                <tr>
                    <th>Tests</th>
                    <th>Passed</th>
                    <th>Failed</th>
                    <th>Skipped</th>
                    <th>Ignored</th>
                    <th>Passrate</th>
                    <th>Runtime</th>
                </tr>
            </thead>
            <tbody>
                {summary}
            </tbody>
        </table>
        <br>
        <table id="results_table" class="asap_table">
            <thead>
                 <tr>
                    <th>Test</th>
                    <th>Time</th>
                    <th>Status</th>
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
WONT_FIX = {}
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
    pass


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
    parser.add_argument('--db-check', action='store_true',
                        help='DB check')
    parser.add_argument('--test-kernel',
                        help='Test specified kernel against db instead of current kernel. works with db.')
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
    log = out[0].decode('ascii')

    with open("%s.log" % logname, 'w') as f1:
        f1.write(log)

    if html:
        with open("%s.html" % logname, 'w') as f2:
            f2.write(Ansi2HTMLConverter().convert(log))

    status = log.splitlines()[-1].strip()
    status = strip_color(status)

    if subp.returncode:
        status = "(%s) %s" % (status, logname + ".log")
        raise ExecCmdFailed(status)

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


def sort_tests(tests, randomize=False):
    if randomize:
        print('Randomizing the tests order')
        random.shuffle(tests)
    else:
        tests.sort(key=lambda x: os.path.basename(x).split('.')[0])


def glob_tests(glob_filter, tests):
    if not glob_filter:
        return
    _tests = []

    if len(glob_filter) == 1 and (' ' in glob_filter[0] or '\n' in glob_filter[0]):
        glob_filter = glob_filter[0].strip().split()

    if len(glob_filter) == 1 and ',' in glob_filter[0]:
        glob_filter = glob_filter[0].split(',')

    for test in tests[:]:
        name = os.path.basename(test)
        if name == MYNAME:
            continue
        for g in glob_filter:
            if fnmatch(name, g):
                _tests.append(test)
                break
    for test in tests[:]:
        if test not in _tests:
            tests.remove(test)


def get_current_fw():
    if "CONFIG" not in os.environ:
        print("ERROR: Cannot ignore by FW, CONFIG environment variable is missing.")
        return None

    config = os.environ.get('CONFIG')
    try:
        with open(config, 'r') as f1:
            for line in f1.readlines():
                if "NIC=" in line:
                    nic = line.split("NIC=")[1].strip()
    except IOError:
        print("ERROR: Cannot read config %s" % config)
        return None

    if not nic:
        print("ERROR: Cannot find NIC in CONFIG.")
        return None

    cmd = "ethtool -i %s | grep firmware-version | awk {'print $2'}" % nic
    return subprocess.check_output(cmd, shell=True).strip()


def update_skip_according_to_db(data):
    if type(data['tests']) is list:
        return

    def kernel_match(kernel1, kernel2):
        if kernel1 in custom_kernels:
            kernel1 = custom_kernels[kernel1]
        # regex issue with strings like "3.10-100+$" so use string compare for exact match.
        if (kernel1.strip('()') == kernel2 or
            re.search("^%s$" % kernel1, kernel2)):
            return True
        return False

    rm = MlxRedmine()
    test_will_run = False
    current_fw_ver = get_current_fw()
    if args.test_kernel:
        current_kernel = args.test_kernel
    else:
        current_kernel = os.uname()[2]

    print("Current fw: %s" % current_fw_ver)
    print("Current kernel: %s" % current_kernel)

    for t in TESTS:
        t = os.path.basename(t)
        if data['tests'][t] is None:
            data['tests'][t] = {}

        if data['tests'][t].get('ignore_for_linust', 0):
            if 'linust' in current_kernel:
                SKIP_TESTS[t] = "Ignore on for-linust kernel"
                continue

        if data['tests'][t].get('ignore_for_upstream', 0):
            if 'upstream' in current_kernel:
                SKIP_TESTS[t] = "Ignore on for-upstream kernel"
                continue

        if 'el' in current_kernel:
            min_kernel = data['tests'][t].get('min_kernel_rhel', None)
        else:
            min_kernel = data['tests'][t].get('min_kernel', None)

        custom_kernels = data.get('custom_kernels', {})
        kernels = data['tests'][t].get('kernels', [])
        if kernels and not min_kernel:
            raise RuntimeError("%s: Specifying kernels without min_kernel is not allowed." % t)

        if min_kernel:
            kernels += custom_kernels.values()
            ok = False
            for kernel in kernels:
                if kernel_match(kernel, current_kernel):
                    ok = True
                    break
            if not ok:
                a = VersionInfo(min_kernel)
                b = VersionInfo(current_kernel)
                if b < a:
                    SKIP_TESTS[t] = "Unsupported kernel version. Minimum %s" % min_kernel
                    continue

        bugs_list = []
        issue_keys = [x for x in data['tests'][t].keys() if isinstance(x, int)]
        for issue in issue_keys:
            for kernel in data['tests'][t][issue]:
                if kernel_match(kernel, current_kernel):
                    bugs_list.append(issue)

        ignore_kernel = data['tests'][t].get('ignore_kernel', {})
        for kernel in ignore_kernel:
            if kernel_match(kernel, current_kernel):
                for bug in ignore_kernel[kernel]:
                    bugs_list.append(bug)

        if current_fw_ver:
            for fw in data['tests'][t].get('ignore_fw', {}):
                if re.search("^%s$" % fw, current_fw_ver):
                    for bug in data['tests'][t]['ignore_fw'][fw]:
                        bugs_list.append(bug)

        for bug in bugs_list:
            task = rm.get_issue(bug)
            if rm.is_issue_wont_fix_or_release_notes(task):
                WONT_FIX[t] = "%s RM #%s: %s" % (task['status']['name'], bug, task['subject'])
            if rm.is_issue_open(task):
                SKIP_TESTS[t] = "RM #%s: %s" % (bug, task['subject'])
            sys.stdout.write('.')
            sys.stdout.flush()

        if t not in SKIP_TESTS:
            test_will_run = True
    print()

    if not test_will_run:
        raise Exception('All Tests will be ignored !')


def get_test_header(fname):
    """Get commented lines from top of the file"""
    data = []
    with open(fname) as f:
        for line in f.readlines():
            if line.startswith('#') or not line.strip():
                data.append(line)
            else:
                break
    return ''.join(data)


def update_skip_according_to_rm():
    print("Check redmine for open issues")
    rm = MlxRedmine()
    for t in TESTS:
        data = get_test_header(t)
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
    print()


def should_ignore_test(name, exclude):
    if name in exclude or name in ' '.join(exclude):
        return True

    for x in exclude:
        if fnmatch(name, x):
            return True

    return False


def save_summary_html():
    number_of_tests = len(TESTS)
    passed_tests = sum(map(lambda test: 'PASSED' in test['status'], TESTS_SUMMARY))
    failed_tests = sum(map(lambda test: 'FAILED' in test['status'], TESTS_SUMMARY))
    skip_tests = sum(map(lambda test: 'SKIP' in test['status'], TESTS_SUMMARY))
    ignored_tests = sum(map(lambda test: 'IGNORED' in test['status'], TESTS_SUMMARY))
    running = number_of_tests - skip_tests - ignored_tests
    if running:
        pass_rate = str(int(passed_tests / float(running) * 100)) + '%'
    else:
        pass_rate = 0
    runtime = sum([t['run_time'] for t in TESTS_SUMMARY])

    summary = SUMMARY_ROW.format(number_of_tests=number_of_tests,
                                 passed_tests=passed_tests,
                                 failed_tests=failed_tests,
                                 skip_tests=skip_tests,
                                 ignored_tests=ignored_tests,
                                 pass_rate=pass_rate,
                                 runtime=runtime)
    results = ''
    for t in TESTS_SUMMARY:
        status = t['status']
        if t.get('test_log', ''):
            status = "<a href='{test_log}'>{status}</a>".format(
                test_log=t['test_log'],
                status=status)
        results += RESULT_ROW.format(test=t['test_name'],
                                     run_time=t['run_time'],
                                     status=status)

    running_tests_names = [t['test_name'] for t in TESTS_SUMMARY]

    for t in TESTS:
        t = os.path.basename(t)
        if t not in running_tests_names:
            status = deco("DID'T RUN", 'darkred', html=True)
            results += RESULT_ROW.format(test=t,
                                         run_time=0.0,
                                         status=status)

    summary_file = "%s/summary.html" % LOGDIR
    with open(summary_file, 'w') as f:
        f.write(HTML.format(style=HTML_CSS, summary=summary, results=results))

    print("Summary: %s" % summary_file)


def prepare_logdir():
    global LOGDIR
    if not args.dry:
        if args.log_dir:
            LOGDIR = args.log_dir
            os.mkdir(LOGDIR)
        else:
            LOGDIR = mkdtemp(prefix='log')
        print("Log dir: " + LOGDIR)


def read_db():
    print("Reading DB: %s" % args.db)
    with open(args.db) as yaml_data:
        data = yaml.safe_load(yaml_data)
        print("Description: %s" % data.get("description", "Empty"))
        return data


def load_tests_from_db(data):
    return [os.path.join(MYDIR, key) for key in data['tests']]


def get_tests():
    global TESTS
    try:
        if args.db:
            data = read_db()
            TESTS = load_tests_from_db(data)
            update_skip_according_to_db(data)
        else:
            TESTS = glob(MYDIR + '/test-*')
            glob_tests(args.glob, TESTS)
            update_skip_according_to_rm()

        return True
    except RuntimeError as e:
        print("ERROR: %s" % e)
        return False


def db_check():
    for test in TESTS:
        name = os.path.basename(test)
        if name in WONT_FIX:
            print("%-62s " % deco(name, 'light-blue'), end=' ')
            print("%-30s" % deco(WONT_FIX[name], 'yellow'))
    return 0


def main():
    exclude = []
    ignore = False

    if not get_tests():
        return 1

    if len(TESTS) == 0:
        print("ERROR: No tests to run")
        return 1

    if args.from_test:
        ignore = True

    if args.exclude:
        exclude.extend(args.exclude)

    exclude.extend(IGNORE_TESTS)

    if not args.db or args.randomize:
        sort_tests(TESTS, args.randomize)

    if args.db_check:
        return db_check()

    print("%-54s %-8s %s" % ("Test", "Time", "Status"))
    failed = False

    for test in TESTS:
        name = os.path.basename(test)
        if ignore:
            if args.from_test != name:
                continue
            ignore = False

        print("%-62s " % deco(name, 'light-blue'), end=' ')
        test_summary = {'test_name': name,
                        'test_log':  '',
                        'run_time':  0.0,
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
            except ExecCmdFailed as e:
                failed = True
                res = 'FAILED'
                out = str(e)

        end_time = datetime.now()
        total_seconds = float("%.2f" % (end_time - start_time).total_seconds())
        test_summary['run_time'] = total_seconds

        total_seconds = "%-7s" % total_seconds
        print("%s " % total_seconds, end=' ')

        test_summary['status'] = format_result(res, skip_reason, html=True)
        print("%-60s" % format_result(res, skip_reason + out))

        TESTS_SUMMARY.append(test_summary)

        if args.stop and failed:
            return 1
    # end test loop

    return failed


def cleanup():
    runtime = sum([t['run_time'] for t in TESTS_SUMMARY])
    if runtime > 0:
        print("runtime: %s" % runtime)
    if args.html and not args.dry:
        save_summary_html()


def signal_handler(signum, frame):
    print("\nterminated")
    cleanup()
    sys.exit(signum)


if __name__ == "__main__":
    args = parse_args()
    prepare_logdir()
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    rc = main()
    cleanup()
    sys.exit(rc)
