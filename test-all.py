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
WONT_FIX = {}
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

class DeviceType(object):
    CX4_LX = "0x1015"
    CX5_PCI_3 = "0x1017"
    CX5_PCI_4 = "0x1019"
    CX6 = "0x101b"
    CX6_DX = "0x101d"
    CX6_LX = "0x101f"
    CX7 = "0x1021"

    @staticmethod
    def get(device_id):
        tmp = {
            DeviceType.CX4_LX: "cx4lx",
            DeviceType.CX5_PCI_3: "cx5",
            DeviceType.CX5_PCI_4: "cx5",
            DeviceType.CX6:    "cx6",
            DeviceType.CX6_DX: "cx6dx",
            DeviceType.CX6_LX: "cx6lx",
            DeviceType.CX7: "cx7",
        }
        return tmp.get(device_id, '')


class ExecCmdFailed(Exception):
    pass


class Test(object):
    def __init__(self, test_file):
        self._test_file = test_file
        self._name = os.path.basename(test_file)
        self._passed = False
        self._failed = False
        self._skip = False
        self._ignore = False
        self._reason = ''
        self.test_log = self._name + '.log'
        self.test_log_html = self._name + '.html'
        self.run_time = 0.0
        self.status = "DIDN'T RUN"

    def run(self, html=False):
        return run_test(self, html)

    @property
    def passed(self):
        return self._passed and not self._failed

    def set_passed(self):
        self._passed = True
        self._failed = False

    @property
    def failed(self):
        return self._failed

    def set_failed(self):
        self._passed = False
        self._failed = True

    @property
    def fname(self):
        return self._test_file

    def exists(self):
        return os.path.exists(self._test_file)

    @property
    def skip(self):
        return self._skip

    def set_skip(self, reason):
        self._skip = True
        self._reason = reason

    @property
    def ignore(self):
        return self._ignore

    def set_ignore(self, reason):
        self._ignore = True
        self._reason = reason

    @property
    def reason(self):
        return self._reason

    @property
    def name(self):
        return self._name

    def __repr__(self):
        return "<Test %s>" % self._name


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
    parser.add_argument('--db', action='append',
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
    parser.add_argument('--loops', default=0, type=int,
                        help='Loop the tests')

    return parser.parse_args()


def run_test(test, html=False):
    cmd = test.fname
    logname = os.path.join(LOGDIR, test.test_log)
    logname_html = os.path.join(LOGDIR, test.test_log_html)
    # piping stdout to file seems to miss stderr msgs to we use pipe
    # and write to file at the end.
    subp = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, close_fds=True)
    out = subp.communicate()
    log = out[0].decode('ascii')

    with open(logname, 'w') as f1:
        f1.write(log)

    if html:
        with open(logname_html, 'w') as f2:
            f2.write(Ansi2HTMLConverter().convert(log))

    status = log.splitlines()[-1].strip()
    status = strip_color(status)

    if subp.returncode:
        raise ExecCmdFailed(status)

    return status


def deco(line, color, html=False):
    if html:
        return "<span style='color: %s'>%s</span>" % (color, line)
    else:
        return "\033[%dm%s\033[0m" % (COLOURS[color], line)


def strip_color(line):
    return re.sub(r"\033\[[0-9 ;]*m", '', line)


def err(line):
    print(deco('ERROR', 'red') + ' %s' % line)


def warn(line):
    print(deco('WARNING', 'yellow') + ' %s' % line)


def format_result(res, out='', html=False):
    res_color = {
        'TEST PASSED': 'green',
        'SKIP':        'yellow',
        'OK':          'green',
        'DRY':         'yellow',
        'FAILED':      'red',
        'TERMINATED':  'red',
        'IGNORED':     'yellow',
        "DIDN'T RUN":  'darkred',
    }
    color = res_color.get(res, 'yellow')
    if "SHOW STOPPER" in res:
        color = 'red'
    if out and "TEST FAILED" not in out and "TEST PASSED" not in out:
        res += ' (%s)' % out
    return deco(res, color, html)


def sort_tests(tests, randomize=False):
    if randomize:
        print('Randomize temporarily disabled. sort by name.')
        randomize = False
    if randomize:
        print('Randomizing the tests order')
        random.shuffle(tests)
    elif type(tests[0]) == str:
        tests.sort(key=lambda x: os.path.basename(x).split('.')[0])
    else:
        tests.sort(key=lambda x: x.name.split('.')[0])


def glob_tests(glob_filter):
    if not glob_filter:
        return
    _tests = []

    if len(glob_filter) == 1 and (' ' in glob_filter[0] or '\n' in glob_filter[0]):
        glob_filter = glob_filter[0].strip().split()
    elif len(glob_filter) == 1 and ',' in glob_filter[0]:
        glob_filter = glob_filter[0].split(',')

    for test in TESTS:
        name = test.name
        for g in glob_filter:
            if fnmatch(name, g):
                _tests.append(test)
                break

    for test in TESTS[:]:
        if test not in _tests:
            TESTS.remove(test)


def get_config():
    if "CONFIG" not in os.environ:
        warn("CONFIG environment variable is missing.")
        return

    config = os.environ.get('CONFIG')
    if os.path.exists(config):
        return config
    elif os.path.exists(os.path.join(MYDIR, config)):
        return os.path.join(MYDIR, config)

    warn("Cannot find config %s" % config)
    return


def get_config_value(key):
    config = get_config()
    if not config:
        return
    try:
        with open(config, 'r') as f1:
            for line in f1.readlines():
                if line.startswith("%s=" % key):
                    val = line.split('=')[1].strip()
                    return val
    except IOError:
        err("Cannot read config %s" % config)
        return

    err("Cannot get %s from CONFIG." % key)


def get_pci(nic):
    return os.path.basename(os.readlink("/sys/class/net/%s/device" % nic))


def get_flow_steering_mode_compat(nic):
    ofed_compat = "/sys/class/net/%s/compat/devlink/steering_mode" % nic
    try:
        with open(ofed_compat, 'r') as f:
            return f.read().strip()
    except IOError:
        pass


def get_flow_steering_mode(nic):
    if not nic:
        return ''
    mode = get_flow_steering_mode_compat(nic)
    if mode:
        return mode
    pci = get_pci(nic)
    cmd = "devlink dev param show pci/%s name flow_steering_mode" % pci
    try:
        output = subprocess.check_output(cmd, shell=True).decode().strip()
    except subprocess.CalledProcessError:
        return
    return output.split()[-1]


def get_current_fw(nic):
    if not nic:
        return ''
    cmd = "ethtool -i %s | grep firmware-version | awk {'print $2'}" % nic
    output = subprocess.check_output(cmd, shell=True).decode().strip()
    if not output:
        err("Cannot get FW version")
    return output


def get_current_nic_type(nic):
    if not nic:
        return ''
    with open('/sys/class/net/%s/device/device' % nic, 'r') as f:
        return f.read().strip()


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
    nic = get_config_value('NIC')
    current_fw_ver = get_current_fw(nic)
    current_nic = DeviceType.get(get_current_nic_type(nic))
    if args.test_kernel:
        current_kernel = args.test_kernel
    else:
        current_kernel = os.uname()[2]
    flow_steering_mode = get_flow_steering_mode(nic)

    custom_kernels = data.get('custom_kernels', {})

    print("nic: %s" % current_nic)
    print("fw: %s" % current_fw_ver)
    print("flow steering: %s" % flow_steering_mode)
    print("kernel: %s" % current_kernel)

    for t in TESTS:
        name = t.name

        if data['tests'][name] is None:
            data['tests'][name] = {}

        ignore_for_linust = data['tests'][name].get('ignore_for_linust', 0)
        ignore_for_upstream = data['tests'][name].get('ignore_for_upstream', 0)

        if ignore_for_linust and ignore_for_upstream:
            raise RuntimeError("%s: Do not ignore on both for_linust and for_upstream." % name)

        if ignore_for_linust and 'linust' in current_kernel:
            t.set_ignore("Ignore on for-linust kernel")
            continue

        if ignore_for_upstream and 'upstream' in current_kernel:
            t.set_ignore("Ignore on for-upstream kernel")
            continue

        ignore_fs = data['tests'][name].get('ignore_flow_steering', '')
        if ignore_fs and (not flow_steering_mode or ignore_fs == flow_steering_mode):
            t.set_ignore("Ignore flow steering mode %s" % ignore_fs)
            continue

        ignore_not_supported = data['tests'][name].get('ignore_not_supported', 0)

        if ignore_not_supported == True:
            t.set_ignore("Not supported")
            continue
        elif type(ignore_not_supported) == list:
            for kernel in ignore_not_supported:
                if kernel_match(kernel, current_kernel):
                    t.set_ignore("Not supported")
                    break
            if t.ignore:
                continue

        if 'el' in current_kernel:
            min_kernel = data['tests'][name].get('min_kernel_rhel', None)
        else:
            min_kernel = data['tests'][name].get('min_kernel', None)

        kernels = data['tests'][name].get('kernels', [])
        if kernels and not min_kernel:
            raise RuntimeError("%s: Specifying kernels without min_kernel is not allowed." % name)

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
                    t.set_ignore("Unsupported kernel version. Minimum %s" % min_kernel)
                    continue

        for nic in data['tests'][name].get('ignore_nic', []):
            if nic == current_nic:
                t.set_ignore("Unsupported nic %s" % nic)
                break
        if t.ignore:
            continue

        bugs_list = []
        # issue number key with list of kernels
        issue_keys = [x for x in data['tests'][name].keys() if isinstance(x, int)]
        for issue in issue_keys:
            for kernel in data['tests'][name][issue]:
                if kernel_match(kernel, current_kernel):
                    bugs_list.append(issue)

        ignore_kernel = data['tests'][name].get('ignore_kernel', {})
        for kernel in ignore_kernel:
            if kernel_match(kernel, current_kernel):
                bugs_list += ignore_kernel[kernel]

        for fw in data['tests'][name].get('ignore_fw', {}):
            if not current_fw_ver or re.search("^%s$" % fw, current_fw_ver):
                bugs_list += data['tests'][name]['ignore_fw'][fw]

        ignore_smfs = data['tests'][name].get('ignore_smfs', [])
        if ignore_smfs and (not flow_steering_mode or flow_steering_mode == 'smfs'):
            for kernel in ignore_smfs:
                if kernel_match(kernel, current_kernel):
                    bugs_list.extend(ignore_smfs[kernel])

        for bug in bugs_list:
            try:
                task = rm.get_issue(bug)
            except ValueError:
                t.set_skip("Cannot fetch RM #%s" % bug)
                continue
            if rm.is_issue_wont_fix_or_release_notes(task):
                WONT_FIX[name] = "%s RM #%s: %s" % (task['status']['name'], bug, task['subject'])
            if rm.is_issue_open(task):
                t.set_skip("RM #%s: %s" % (bug, task['subject']))
                break
            sys.stdout.write('.')
            sys.stdout.flush()
    print()


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
        data = get_test_header(t.fname)
        name = t.name
        bugs = re.findall(r"#\s*Bug SW #([0-9]+):", data)
        for b in bugs:
            task = rm.get_issue(b)
            sys.stdout.write('.')
            sys.stdout.flush()
            if rm.is_issue_open(task):
                t.set_skip("RM #%s: %s" % (b, task['subject']))
                break

        if not t.skip and 'IGNORE_FROM_TEST_ALL' in data:
            t.set_ignore("IGNORE_FROM_TEST_ALL")
    print()


def ignore_excluded(exclude):
    if not exclude:
        return
    if type(exclude[0]) is str and ',' in exclude[0]:
        exclude = exclude[0].split(',')
    for item in exclude:
        for t in TESTS:
            if t.name == item or fnmatch(t.name, item):
                t.set_ignore('excluded')


def save_summary_html():
    number_of_tests = len(TESTS)
    passed_tests = sum(map(lambda test: test.passed, TESTS))
    failed_tests = sum(map(lambda test: test.failed, TESTS))
    skip_tests = sum(map(lambda test: test.skip, TESTS))
    ignored_tests = sum(map(lambda test: test.ignore, TESTS))
    running = number_of_tests - skip_tests - ignored_tests
    if running:
        pass_rate = str(int(passed_tests / float(running) * 100)) + '%'
    else:
        pass_rate = 0
    runtime = round(sum([t.run_time for t in TESTS]), 2)

    summary = SUMMARY_ROW.format(number_of_tests=number_of_tests,
                                 passed_tests=passed_tests,
                                 failed_tests=failed_tests,
                                 skip_tests=skip_tests,
                                 ignored_tests=ignored_tests,
                                 pass_rate=pass_rate,
                                 runtime=runtime)
    results = ''
    for t in TESTS:
        status = t.status
        if status in ('UNKNOWN', "DIDN'T RUN"):
            status = format_result(status, '', html=True)

        logname = os.path.join(LOGDIR, t.test_log_html)
        if os.path.exists(logname):
            status = "<a href='{test_log}'>{status}</a>".format(
                test_log=t.test_log_html,
                status=status)

        results += RESULT_ROW.format(test=t.name,
                                     run_time=t.run_time,
                                     status=status)

    summary_file = "%s/summary.html" % LOGDIR
    with open(summary_file, 'w') as f:
        f.write(HTML.format(style=HTML_CSS, summary=summary, results=results))
    return summary_file


def prepare_logdir():
    if args.dry:
        return
    if args.log_dir:
        logdir = args.log_dir
        os.mkdir(logdir)
    else:
        logdir = mkdtemp(prefix='log')
    print("Log dir: " + logdir)
    return logdir


def merge_data(data, out):
    for key in data:
        if key not in out:
            out[key] = data[key]
        else:
            if type(data[key]) is str:
                continue
            elif type(data[key]) is list:
                out[key] += data[key]
            else:
                out[key].update(data[key])
    return out


def get_db_path(db):
    db2 = os.path.join(MYDIR, 'databases', db)
    if not os.path.exists(db):
        if os.path.exists(db2):
            db = db2
        else:
            err("Cannot find db %s" % db)
            return
    return db


DB_PATH = None
def read_db():
    global DB_PATH
    out = {}
    if len(args.db) == 1 and '*' in args.db[0]:
        dbs = glob(args.db[0]) or glob(os.path.join(MYDIR, 'databases', args.db[0]))
    elif len(args.db) == 1 and ',' in args.db[0]:
        dbs = args.db[0].split(',')
    else:
        dbs = args.db

    multi = len(dbs) > 1
    for db in dbs:
        db = get_db_path(db)
        if not db:
            return {}
        if not DB_PATH:
            DB_PATH = os.path.dirname(db)
        if multi and 'mini_reg' in db:
            continue
        if multi and 'ignore' in db and not args.db_check:
            continue
        print("Reading DB: %s" % db)
        with open(db) as yaml_data:
            data = yaml.safe_load(yaml_data)
            print("Description: %s" % data.get("description", "Empty"))
            # handle special case. if merging multi dbs skip lists like mini reg.
            if multi and (type(data['tests']) is list):
                print("Skip db")
                continue
            merge_data(data, out)
    return out


MINI_REG_LIST = []
def read_mini_reg_list():
    global MINI_REG_LIST

    if not DB_PATH:
        return

    mini = os.path.join(DB_PATH, 'mini_regression.yaml')
    if not os.path.exists(mini):
        return

    with open(mini) as f:
        data = yaml.safe_load(f)
        if type(data['tests']) is dict:
            MINI_REG_LIST = data['tests'].keys()
        if type(data['tests']) is list:
            MINI_REG_LIST = data['tests']


def load_tests_from_db(data):
    subfolder = data.get('tests_subfolder', '')
    tests = [Test(os.path.join(MYDIR, subfolder, key)) for key in data['tests']]
    for test in tests:
        if not test.exists():
            warn("Cannot find test %s" % test.name)
    return tests


def get_tests():
    global TESTS
    try:
        if args.db:
            data = read_db()
            read_mini_reg_list()
            if 'tests' in data:
                TESTS = load_tests_from_db(data)
                ignore_excluded(data.get('ignore', []))
                update_skip_according_to_db(data)
        else:
            tmp = glob(MYDIR + '/test-*.sh')
            TESTS = [Test(t) for t in tmp]
            glob_tests(args.glob)
            update_skip_according_to_rm()

        return True
    except RuntimeError as e:
        err("%s" % e)
        return False


def print_test_line(name, reason):
    print("%-62s " % deco(name, 'light-blue'), end=' ')
    print("%-30s" % deco(reason, 'yellow'))


def db_check():
    all_tests = glob(MYDIR + '/test-*.sh')
    sort_tests(all_tests)
    for test in TESTS:
        if test.fname in all_tests:
            all_tests.remove(test.fname)

    for test in all_tests:
        name = os.path.basename(test)
        print_test_line(name, "Missing in db")

    for test in TESTS:
        name = test.name
        if test.name in WONT_FIX:
            print_test_line(name, WONT_FIX[name])
    return 0


def pre_quick_status_updates():
    if not args.html or args.dry:
        return

    for test in TESTS:
        res = ''
        reason = ''

        if not test.exists():
            res = 'FAILED'
            reason = 'Cannot find test'
        elif test.ignore:
            res = 'IGNORED'
            reason = test.reason
        elif test.skip:
            res = 'SKIP'
            reason = test.reason
        else:
            continue

        test.status = format_result(res, reason, html=True)


def main():
    ignore = False

    if not get_tests():
        return 1

    if len(TESTS) == 0:
        err("No tests to run")
        return 1
    except RuntimeError, e:
        print "ERROR: %s" % e
        return 1

    if args.from_test:
        ignore = True

    ignore_excluded(args.exclude)

    if not args.db or args.randomize:
        sort_tests(TESTS, args.randomize)

    if args.db_check:
        # we dont sort db file (we should probably if dict and not list) so do it now.
        sort_tests(TESTS)
        return db_check()

    print("%-54s %-8s %s" % ("Test", "Time", "Status"))
    failed = False

    if not args.loops:
        args.loops = 1

    for loop in range(args.loops):
        pre_quick_status_updates()

        for test in TESTS:
            name = test.name
            if ignore:
                if args.from_test != name:
                    continue
                ignore = False

            print("%-62s " % deco(name, 'light-blue'), end=' ')
            sys.stdout.flush()

            test.status = 'UNKNOWN'

            # Pre update summary report before running next test.
            # In case we crash we still might want the report.
            if args.html and not args.dry:
                save_summary_html()

            res = ''
            reason = ''
            logname = ''
            total_seconds = 0.0

            if not test.exists():
                failed = True
                test.set_failed()
                res = 'FAILED'
                reason = 'Cannot find test'
            elif test.ignore:
                res = 'IGNORED'
                reason = test.reason
            elif test.skip:
                res = 'SKIP'
                reason = test.reason
            elif args.dry:
                res = 'DRY'
            else:
                start_time = datetime.now()
                logname = os.path.join(LOGDIR, test.test_log)
                try:
                    reason = test.run(args.html)
                    res = 'TEST PASSED'
                    test.set_passed()
                except ExecCmdFailed as e:
                    failed = True
                    test.set_failed()
                    res = 'FAILED'
                    reason = str(e)
                end_time = datetime.now()
                total_seconds = float("%.2f" % (end_time - start_time).total_seconds())

            test.run_time = total_seconds
            total_seconds = "%-7s" % total_seconds
            print("%s " % total_seconds, end=' ')

            if (test.name in MINI_REG_LIST) and (test.skip or test.ignore or test.failed):
                res = "SHOW STOPPER - %s" %res
            test.status = format_result(res, reason, html=True)
            print("%s %s" % (format_result(res, reason), logname))

            if args.stop and failed:
                return 1
        # end test loop

        if failed:
            break
    # end loops

    return failed


def cleanup():
    runtime = round(sum([t.run_time for t in TESTS]), 2)
    if runtime > 0:
        print("runtime: %s" % runtime)
    if args.html and not args.dry:
        summary_file = save_summary_html()
        print("Summary: %s" % summary_file)


def signal_handler(signum, frame):
    print("\nterminated")
    cleanup()
    sys.exit(signum)


if __name__ == "__main__":
    args = parse_args()
    LOGDIR = prepare_logdir()
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    rc = main()
    cleanup()
    sys.exit(rc)
