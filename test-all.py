#!/usr/bin/python

from __future__ import print_function

import os
import re
import sys
import yaml
import random
import signal
import argparse
import subprocess
from copy import copy
from glob import glob
from fnmatch import fnmatch
from tempfile import mkdtemp
from datetime import datetime
from semver import VersionInfo
from requests.exceptions import ConnectionError
from mlxredmine import MlxRedmine
from ansi2html import Ansi2HTMLConverter

# HTML components
ENV_ROW = """
<tr>
    <td>{key}</td>
    <td>{val}</td>
</tr>"""

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
      .asap_table th { text-align: left; background-color: gray; }
      .asap_table td { background-color: lightgray; }
      .asap_table td:first-child { font-weight: bold; }
      .asap_table td.testname { font-weight: bold; white-space: nowrap; }
      table#summary_table td { font-weight: bold; }
    </style>
"""

RERUN_HTML = """
        <h2>Rerun Results</h2>
        <table id="rerun_table" class="asap_table">
            <thead>
                 <tr>
                    <th>Test</th>
                    <th>Time</th>
                    <th>Status</th>
                 </tr>
            </thead>
            <tbody>
                {rerun_results}
            </tbody>
        </table>
"""

HTML = """<!DOCTYPE html>
<html>
    <head>
        <title>Summary</title>
        {style}
    </head>
    <body>
        <h2>Environment</h2>
        <table id="env_table" class="asap_table">
            <thead>
                <tr>
                    <th>Name</th>
                    <th>Value</th>
                </tr>
            </thead>
            <tbody>
                {envinfo}
            </tbody>
        </table>
        <h2>Summary</h2>
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
        <h2>Tests Results</h2>
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
        {rerun}
    </body>
</html>
"""

MYNAME = os.path.basename(__file__)
MYDIR = os.path.abspath(os.path.dirname(__file__))
LOGDIR = ''
TESTS = []
RERUN_TESTS = []
WONT_FIX = {}
COLOURS = {
    "black": 30,
    "red": 31,
    "green": 32,
    "yellow": 33,
    "blue": 34,
    "magenta": 25,
    "cyan": 36,
    "gray": 37,
    "dark-gray": 90,
    "light-red": 91,
    "light-green": 92,
    "light-yellow": 93,
    "light-blue": 94,
    "light-magenta": 95,
    "light-cyan": 96,
    "white": 97,
}

DB_PATH = None
MINI_REG_LIST = []
IGNORE_LIST = []
TEST_TIMEOUT_MAX = 900
KMEMLEAK_SYSFS = "/sys/kernel/debug/kmemleak"
TAG_COLOR = "yellow"
RERUN_TAG = "*rerun"
INJECT_TAG = "*inject"
envinfo = {}
kmemleak_ignore = os.path.join(MYDIR, "kmemleak.ignore")

TIME_DURATION_UNITS = (
    ('h', 60*60),
    ('m', 60),
    ('s', 1)
)

try:
    with open('/labhome/roid/scripts/redmine/redmine_key.txt') as f:
        RM_API_KEY = f.read().strip()
except:
    RM_API_KEY = None


def human_time_duration(seconds):
    if seconds == 0:
        return 'inf'
    parts = []
    for unit, div in TIME_DURATION_UNITS:
        amount, seconds = divmod(int(seconds), div)
        if amount > 0:
            parts.append('{}{}'.format(amount, unit))
    return ''.join(parts)


class DeviceType(object):
    CX4_LX = "0x1015"
    CX5_PCI_3 = "0x1017"
    CX5_PCI_4 = "0x1019"
    CX6 = "0x101b"
    CX6_DX = "0x101d"
    CX6_LX = "0x101f"
    CX7 = "0x1021"
    BF2 = "0xa2d6"
    BF3 = "0xa2dc"
    devices = {
        CX4_LX:    "cx4lx",
        CX5_PCI_3: "cx5",
        CX5_PCI_4: "cx5",
        CX6:       "cx6",
        CX6_DX:    "cx6dx",
        CX6_LX:    "cx6lx",
        CX7:       "cx7",
        BF2:       "bf2",
        BF3:       "bf3",
    }

    @staticmethod
    def get(device_id):
        return DeviceType.devices.get(device_id, '')

    @staticmethod
    def is_valid_compare(nic1, nic2):
        if nic1.startswith('cx') and nic2.startswith('cx'):
            return True
        if nic1.startswith('bf') and nic2.startswith('bf'):
            return True
        return False

    @staticmethod
    def __normalize(nic):
        if nic == 'bf2':
            return 'cx6dx'
        elif nic == 'bf3':
            return 'cx7'
        return nic

    @staticmethod
    def cmp(nic1, nic2):
        """
        -1   - nic1 < nic2
        0    - nic1 == nic2
        1    - nic1 > nic2
        """
        nic1 = DeviceType.__normalize(nic1)
        nic2 = DeviceType.__normalize(nic2)
        if not DeviceType.is_valid_compare(nic1, nic2):
            raise AttributeError("Invalid nics for comparison %s %s" % (nic1, nic2))
        major1 = nic1[2]
        major2 = nic2[2]
        if major1 < major2:
            return -1
        if major1 > major2:
            return 1
        minor1 = nic1[3:]
        minor2 = nic2[3:]
        if minor1 == minor2:
            return 0
        if minor1 == "" and minor2 != "":
            return -1
        if minor1 != "" and minor2 == "":
            return 1
        if minor1 == "lx" and minor2 == "dx":
            return -1
        if minor1 == "dx" and minor2 == "lx":
            return 1
        raise RuntimeError("Cannot compare nics %s %s" % (nic1, nic2))

    @staticmethod
    def lte(nic1, nic2):
        return DeviceType.cmp(nic1, nic2) <= 0

    @staticmethod
    def gte(nic1, nic2):
        return DeviceType.cmp(nic1, nic2) >= 0


class ExecCmdFailed(Exception):
    pass


class Test(object):
    def __init__(self, test_file, opts={}):
        self._test_file = test_file
        self._name = os.path.basename(test_file)
        self._relpath = MYDIR
        self._relname = os.path.relpath(test_file, self._relpath)
        self.init_state()
        self.issues = []
        self.set_logs()
        self.iteration = 0
        self.opts = opts or {}
        self.tag = ''
        self.group = ''
        self.cmd = self._test_file

    def init_state(self):
        self._passed = False
        self._failed = False
        self._skip = False
        self._wont_fix = False
        self._ignore = False
        self._reason = ''
        self.run_time = 0.0
        self.status = "DIDN'T RUN"

    def set_logs(self, post=0):
        post_log = '.log' if not post else '.%s.log' % post
        post_html = '.html' if not post else '.%s.html' % post
        self.test_log = self._name + post_log
        self.test_log_html = self._name + post_html

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

    def set_failed(self, reason):
        self._passed = False
        self._failed = True
        self._reason = reason

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

    def unset_skip(self):
        self._skip = False

    @property
    def wont_fix(self):
        return self._wont_fix

    def set_wont_fix(self):
        self._wont_fix = True

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

    @property
    def relname(self):
        return self._relname

    def __repr__(self):
        return "<Test %s>" % self._name


def kmsg(msg):
    with open("/dev/kmsg", "w") as f:
        f.write(msg+"\n")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='verbose output')
    parser.add_argument('--stop', '-s', action='store_true',
                        help='stop on first error')
    parser.add_argument('--dry', '-d', action='store_true',
                        help='not to actually run the test')
    parser.add_argument('--from-test', '-f',
                        help='start from test')
    parser.add_argument('--to-test', '-t',
                        help='stop at a test')
    parser.add_argument('--inject-test', '-j',
                        help='Inject provided test after each test planned to run')
    parser.add_argument('--exclude', '-e', action='append',
                        help='exclude tests')
    parser.add_argument('--glob', '-g', action='append',
                        help='glob of tests')
    parser.add_argument('--db', nargs='+',
                        help='DB file to read for tests to run')
    parser.add_argument('--db-check', action='store_true',
                        help='DB check')
    parser.add_argument('--test-kernel',
                        help='Test specified kernel instead of current kernel. works with db.')
    parser.add_argument('--test-nic',
                        help='Test specified nic instead of current nic. works with db.')
    parser.add_argument('--test-fw',
                        help='Test specified fw instead of current fw. works with db.')
    parser.add_argument('--test-simx', action='store_true', help="Test SimX.")
    parser.add_argument('--log_dir',
                        help='Log dir to save all logs under')
    parser.add_argument('--html', action='store_true',
                        help='Save log files in HTML and a summary')
    parser.add_argument('--randomize', '-r', action='store_true',
                        help='Randomize the order of the tests')
    parser.add_argument('--group', action='store_true',
                        help='Sort tests by group')
    parser.add_argument('--loops', default=0, type=int,
                        help='Loop the tests. stop if loop fails.')
    parser.add_argument('--run-skipped', action='store_true',
                        help='Run tests that are skipped by open issue.')
    parser.add_argument('--rerun-failed', action='store_true',
                        help='Rerun failed test.')

    return parser.parse_args()


def get_better_status(rc, log):
    status = log.splitlines()[-1].strip()
    status = strip_color(status)
    lookback = 7

    if rc:
        # look for better status
        for line in log.splitlines()[-lookback:]:
            line = strip_color(line.strip())
            if line.startswith('ERROR: '):
                status = line
                break

        return status

    if 'TEST PASSED' not in status:
        # maybe some cleanup prints so look a bit back but not too much
        for line in log.splitlines()[-lookback:]:
            line = strip_color(line.strip())
            if line == 'TEST PASSED':
                status = line
                break

    return status


def get_kmemleak_info():
    if not os.path.exists(KMEMLEAK_SYSFS):
        return ''

    data = ''
    with open(KMEMLEAK_SYSFS) as f:
        data = f.read().strip()

    if data:
        data = "\n\n\n%s\n%s\n" % ("kmemleak trace", data)
        with open(KMEMLEAK_SYSFS, 'w') as f:
            f.write('clear')

    return data


def run_test(test, html=False):
    cmd = test.cmd

    env = os.environ.copy()
    env.update(test.opts.get('env', {}))
    test_timeout = test.opts.get('timeout', TEST_TIMEOUT_MAX)

    logname = os.path.join(LOGDIR, test.test_log)
    logname_html = os.path.join(LOGDIR, test.test_log_html)
    # piping stdout to file seems to miss stderr msgs to we use pipe
    # and write to file at the end.
    timedout = False
    terminated = False
    subp = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, close_fds=True, env=env)
    try:
        try:
            out, _ = subp.communicate(timeout=test_timeout)
        except subprocess.TimeoutExpired as e:
            subp.kill()
            out = e.output
            try:
                out, _ = subp.communicate(timeout=1)
            except subprocess.TimeoutExpired as e:
                subp.terminate()
                out = e.output
                kmsg("Test got terminated")
                terminated = True
            timedout = True
    except AttributeError:
        # timeout introduced in python3.3
        out, _ = subp.communicate()

    if args.dry:
        return "nothing"

    if not out:
        raise ExecCmdFailed("Empty result")

    rc = subp.returncode
    log = out.decode('ascii', 'ignore')
    if not log:
        raise ExecCmdFailed("Empty output")

    if timedout:
        if terminated:
            status = "Test timed out and got terminated"
        else:
            status = "Test timed out and got killed"
        log += "\n%s\n" % deco("ERROR: %s" % status, 'red')
        rc = 1
    else:
        # not timedout
        status = get_better_status(rc, log)
        memleak = get_kmemleak_info()
        if memleak:
            log += "\n\n"
            unref_count = memleak.count("unreferenced object")
            ignore_count = 0
            with open(kmemleak_ignore) as f:
                for line in f.readlines():
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    ignore_count += memleak.count(line)
            if unref_count == ignore_count:
                log += "Found %d known memory leaks\n\n" % ignore_count
            else:
                status = "kmemleak found issues"
                rc = 1
            log += memleak

    with open(logname, 'w') as f1:
        f1.write(log)

    if html:
        with open(logname_html, 'w') as f2:
            f2.write(Ansi2HTMLConverter().convert(log))

    if rc:
        raise ExecCmdFailed(status)

    return status


def deco(line, color, html=False):
    if not line or not color:
        return line
    if html:
        return "<span style='color: %s'>%s</span>" % (color, line)
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
        'DRY':         'gray',
        'FAILED':      'red',
        'TERMINATED':  'red',
        'IGNORED':     'gray',
        "DIDN'T RUN":  'darkred',
    }

    color = res_color.get(res, 'yellow')

    if "SKIP SHOW STOPPER" in res:
        color = 'yellow'
    elif "IGNORED SHOW STOPPER" in res:
        color = 'gray'
    elif "FAILED SHOW STOPPER" in res:
        color = 'red'

    if out and "TEST FAILED" not in out and "TEST PASSED" not in out:
        res += ' (%s)' % out

    return deco(res, color, html)


def sort_tests(tests, randomize=False):
    def cmp1(x):
        return x[:-3].replace('-', 'a')

    if randomize:
        warn('Randomize temporarily disabled. sort by name.')
        randomize = False
    if randomize:
        print('Randomizing the tests order')
        random.shuffle(tests)
    elif type(tests[0]) == str:
        key=lambda x: cmp1(os.path.basename(x))
    elif args.group:
        key=lambda x: cmp1(x.group + x.name)
    else:
        key=lambda x: cmp1(x.name)

    tests.sort(key=key)


def glob_tests(glob_filter):
    if not glob_filter:
        return
    _tests = []

    if len(glob_filter) == 1 and (' ' in glob_filter[0] or '\n' in glob_filter[0]):
        glob_filter = glob_filter[0].strip().split()
    elif len(glob_filter) == 1 and ',' in glob_filter[0]:
        glob_filter = glob_filter[0].split(',')

    for test in TESTS:
        for g in glob_filter:
            if fnmatch(test.name, g):
                _tests.append(test)
                break

    for test in TESTS[:]:
        if test not in _tests:
            TESTS.remove(test)


def get_config():
    if 'CONFIG' not in os.environ:
        if not (args.dry or args.db_check):
            raise RuntimeError("CONFIG environment variable is missing.")
        return

    config = os.environ['CONFIG']
    if os.path.exists(config):
        return config
    elif os.path.exists(os.path.join(MYDIR, config)):
        return os.path.join(MYDIR, config)

    raise RuntimeError("Cannot find config %s" % config)


def get_config_value(key):
    config = get_config()
    if not config:
        return
    try:
        with open(config, 'r') as f1:
            for line in f1.readlines():
                if line.startswith("%s=" % key):
                    return line.split('=')[1].strip().strip('"')
    except IOError:
        err("Cannot read config %s" % config)


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


def check_simx(nic):
    if not nic:
        return False
    current_pci = get_pci(nic)
    cmd = "lspci -s %s -vvv | grep SimX" % current_pci
    try:
        output = subprocess.check_output(cmd, shell=True).decode().strip()
    except subprocess.CalledProcessError:
        return False
    return True


def fix_path_from_config():
    path = get_config_value('PATH')
    if not path:
        return
    newp = []
    for p in path.split(os.pathsep):
        if p == "$PATH":
            continue
        newp.append(p)
    os.environ['PATH'] = os.pathsep.join(newp) + os.pathsep + os.environ['PATH']


DPDK_LIB_DIR = "/opt/mellanox/dpdk"
DOCA_LIB_DIR = "/opt/mellanox/doca"


def get_dpdk_version():
    g = glob(os.path.join(DPDK_LIB_DIR, '**', 'libdpdk.pc'), recursive=True)
    if g:
        with open(g[0]) as f:
            for line in f.readlines():
                if 'version:' in line.lower():
                    return 'DPDK_%s' % line.split()[1]
    return ''


def get_doca_version():
    g = glob(os.path.join(DOCA_LIB_DIR, '**', 'doca.pc'), recursive=True)
    if g:
        with open(g[0]) as f:
            for line in f.readlines():
                if 'version:' in line.lower():
                    return 'DOCA_%s' % line.split()[1]
    return ''


def get_ovs_version():
    try:
        output = subprocess.check_output("ovs-vswitchd --version", shell=True).decode().strip()
    except subprocess.CalledProcessError:
        return ''
    return output.splitlines()[0].split()[-1]


def get_mofed_version():
    try:
        output = subprocess.check_output("ofed_info -s", shell=True).decode().strip()
    except subprocess.CalledProcessError:
        return ''
    return output.strip(':')


__is_bf_host = None
def is_bf_host():
    global __is_bf_host

    if __is_bf_host is not None:
        return __is_bf_host

    try:
        subprocess.check_output("lspci 2>/dev/null | grep -m1 -wq \"Mellanox .* BlueField.* integrated\"", shell=True)
        __is_bf_host = True
    except subprocess.CalledProcessError:
        __is_bf_host = False
    return __is_bf_host


def get_current_state():
    global envinfo
    global current_nic
    global current_fw_ver
    global current_kernel
    global flow_steering_mode
    global simx_mode
    global dpdk_mode

    _distro = get_distro()
    if 'PRETTY_NAME' in _distro:
        distro = _distro['PRETTY_NAME']
    else:
        distro = ''

    fix_path_from_config()

    nic = get_config_value('NIC')
    dpdk_mode = get_config_value('DPDK') == '1'

    current_fw_ver = args.test_fw or get_current_fw(nic)
    current_nic = args.test_nic if args.test_nic else DeviceType.get(get_current_nic_type(nic))
    current_kernel = args.test_kernel if args.test_kernel else os.uname()[2]
    flow_steering_mode = get_flow_steering_mode(nic)
    simx_mode = True if args.test_simx else check_simx(nic)

    envinfo.update({
        'dpdk version': get_dpdk_version(),
        'doca version': get_doca_version(),
        'ovs version': get_ovs_version(),
        'mofed version': get_mofed_version(),
        'nic': current_nic,
        'firmware version': current_fw_ver,
        'kernel': current_kernel,
        'flow steering mode': flow_steering_mode,
        'simx': simx_mode,
        'distro': distro,
        'config dpdk': dpdk_mode,
        'is_bf_host': is_bf_host(),
    })

    if distro:
        print(distro)
    print("nic: %s" % current_nic)
    print("fw: %s" % current_fw_ver)
    print("flow steering: %s" % flow_steering_mode)
    print("kernel: %s" % current_kernel)
    if simx_mode:
        print("simx mode")


def update_skip_according_to_db(rm, _tests, data):
    if type(data['tests']) is list:
        return

    def kernel_match(kernel1, kernel2):
        if kernel1 in custom_kernels:
            kernel1 = custom_kernels[kernel1]
        if kernel1 in kernel2:
            return True
        # regex issue with strings like "3.10-100+$" so use string compare for exact match.
        if (kernel1.strip('()') == kernel2 or re.search("^%s$" % kernel1, kernel2)):
            return True
        return False

    def should_ignore(key, t):
        if key is True:
            t.set_ignore("Not supported")
            return True
        elif type(key) == str:
            t.set_ignore("Not supported: %s" % key)
            return True
        elif type(key) == list:
            for k in key:
                if k == flow_steering_mode:
                    t.set_ignore("Unsupported flow steering mode %s" % k)
                    return True
                if k == current_nic:
                    t.set_ignore("Unsupported nic %s" % k)
                    return True
                if kernel_match(k, current_kernel):
                    t.set_ignore("Unsupported kernel %s" % k)
                    return True
        return False

    def fw_ignore(min_fw, current_fw_ver, t):
        if current_fw_ver:
            cx_type = min_fw.split('.')[0]
            cx_ver = min_fw[min_fw.index('.')+1:]
            current_cx_type = current_fw_ver.split('.')[0]
            current_cx_ver = current_fw_ver[current_fw_ver.index('.')+1:]
            if cx_type in (current_cx_type, 'xx') and VersionInfo(current_cx_ver) < VersionInfo(cx_ver):
                t.set_ignore("Unsupported fw version. Minimum %s" % min_fw)
        else:
            t.set_failed("Invalid fw to compare")

    custom_kernels = data.get('custom_kernels', {})
    is_debug_kernel = '_debug_' in current_kernel and '_min_debug_' not in current_kernel
    print_newline = False

    for t in _tests:
        if t.ignore:
            continue

        name = t.name
        opts = t.opts
        bugs_list = []

        ignore_for_linust = opts.get('ignore_for_linust', 0)
        ignore_for_upstream = opts.get('ignore_for_upstream', 0)
        ignore_for_debug_kernel = opts.get('ignore_for_debug_kernel', 0)

        if ignore_for_debug_kernel and is_debug_kernel:
            t.set_ignore("Ignore on debug kernel")

        if ignore_for_linust and ignore_for_upstream:
            raise RuntimeError("%s: Do not ignore on both for_linust and for_upstream." % name)

        if ignore_for_linust and 'linust' in current_kernel:
            t.set_ignore("Ignore on for-linust kernel")
            continue

        if ignore_for_upstream and 'upstream' in current_kernel:
            t.set_ignore("Ignore on for-upstream kernel")
            continue

        ignore_fs = opts.get('ignore_flow_steering', '')
        if ignore_fs and (not flow_steering_mode or ignore_fs == flow_steering_mode):
            t.set_ignore("Ignore flow steering mode %s" % ignore_fs)
            continue

        ignore_not_supported = opts.get('ignore_not_supported', 0)

        if should_ignore(ignore_not_supported, t):
            continue

        ignore_failed = opts.get('ignore_failed', 0)
        if ignore_failed:
            t.set_skip("Test failed and first ignored - check manually")

        if is_bf_host():
            min_kernel = ''
        elif re.search(r'\.el[0-9]+[\.|_]', current_kernel):
            min_kernel = str(opts.get('min_kernel_rhel', ''))
        elif 'bluefield' in current_kernel:
            min_kernel = str(opts.get('min_kernel_bf', ''))
        else:
            min_kernel = str(opts.get('min_kernel', ''))

        if 'for_upstream' in min_kernel:
            if 'for_upstream' in current_kernel:
                try:
                    d1 = re.search(r'(\d\d\d\d)_(\d\d)_(\d\d)', min_kernel).group()
                    d1 = datetime.strptime(d1, '%Y_%m_%d')
                    d2 = re.search(r'(\d\d\d\d)_(\d\d)_(\d\d)', current_kernel).group()
                    d2 = datetime.strptime(d2, '%Y_%m_%d')
                    if d1 > d2:
                        t.set_ignore("Unsupported kernel version. Minimum %s" % min_kernel)
                except AttributeError as e:
                    t.set_failed("Failed to parse datetime from kernel")
        elif 'for_linust' in min_kernel:
            if 'for_linust' in current_kernel:
                try:
                    d1 = re.search(r'(\d\d\d\d)_(\d\d)_(\d\d)', min_kernel).group()
                    d1 = datetime.strptime(d1, '%Y_%m_%d')
                    d2 = re.search(r'(\d\d\d\d)_(\d\d)_(\d\d)', current_kernel).group()
                    d2 = datetime.strptime(d2, '%Y_%m_%d')
                    if d1 > d2:
                        t.set_ignore("Unsupported kernel version. Minimum %s" % min_kernel)
                except AttributeError as e:
                    t.set_failed("Failed to parse datetime from kernel")
        elif min_kernel:
            # dont match min_kernel with custom_kernels list.
            kernels = []
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

        for nic in opts.get('ignore_nic', []):
            if nic == current_nic:
                t.set_ignore("Unsupported nic %s" % nic)
                break

        min_nic = opts.get('min_nic', None)
        if min_nic:
            try:
                if not DeviceType.gte(current_nic, min_nic):
                    t.set_ignore("Unsupported nic %s" % current_nic)
            except AttributeError as e:
                t.set_failed(str(e))

        max_nic = opts.get('max_nic', None)
        if max_nic:
            try:
                if not DeviceType.lte(current_nic, max_nic):
                    t.set_ignore("Unsupported nic %s" % current_nic)
            except AttributeError as e:
                t.set_failed(str(e))

        min_fw = opts.get('min_fw', None)
        if min_fw and not simx_mode:
            fw_ignore(min_fw, current_fw_ver, t)

        ignore = opts.get('ignore', [])
        for i in ignore:
            if 'rm' in i and 'reason' in i:
                t.set_failed("Invalid ignore key rm and reason.")
                break

            ignore_count = 0
            for k in i:
                v = i[k]
                if k == 'nic':
                    if v == current_nic:
                        ignore_count += 1
                elif k == 'fw':
                    if simx_mode:
                        continue
                    if not current_fw_ver or re.search("^%s$" % v, current_fw_ver):
                        ignore_count += 1
                elif k == 'steering':
                    if not flow_steering_mode or v == flow_steering_mode:
                        ignore_count += 1
                elif k == 'kernel':
                    if kernel_match(str(v), current_kernel):
                        ignore_count += 1
                elif k == 'rm':
                    ignore_count += 1
                elif k == 'reason':
                    ignore_count += 1
                elif k == 'simx_min_ver':
                    if not simx_mode:
                        continue
                    fw_ignore(v, current_fw_ver, t)
                    # currently fw_ignore does the ignore so not increasing ignore_count.
                elif k == 'simx':
                    if (simx_mode and v) or (not simx_mode and not v):
                        ignore_count += 1
                elif k == 'dpdk':
                    if v == dpdk_mode:
                        ignore_count += 1
                else:
                    t.set_failed("Invalid ignore key: %s=%s" % (k, v))
                    break

            # check if all ignore conditions matched.
            if ignore_count == len(i):
                if 'rm' in i:
                    bugs_list.append(i['rm'])
                elif 'reason' in i:
                    t.set_ignore(i['reason'])
                else:
                    tmp = ['%s=%s' % (k, i[k]) for k in i]
                    t.set_ignore("Ignore %s" % ' '.join(tmp))

        if t.ignore or t.failed:
            continue

        # issue number key with list of kernels
        issue_keys = [x for x in opts.keys() if isinstance(x, int)]
        for issue in issue_keys:
            for kernel in opts[issue]:
                if kernel_match(kernel, current_kernel):
                    bugs_list.append(issue)

        ignore_kernel = opts.get('ignore_kernel', {})
        for kernel in ignore_kernel:
            if kernel_match(kernel, current_kernel):
                bugs_list.extend(ignore_kernel[kernel])

        if not simx_mode:
            for fw in opts.get('ignore_fw', {}):
                if not current_fw_ver or re.search("^%s$" % fw, current_fw_ver):
                    bugs_list.extend(opts['ignore_fw'][fw])

        ignore_smfs = opts.get('ignore_smfs', [])
        if ignore_smfs and (not flow_steering_mode or flow_steering_mode == 'smfs'):
            for key in ignore_smfs:
                if key == current_nic or kernel_match(key, current_kernel):
                    bugs_list.extend(ignore_smfs[key])

        if not rm:
            continue

        for bug in bugs_list:
            try:
                task = rm.get_issue(bug)
                t.issues.append(task)
            except Exception as e:
                t.set_skip("Cannot fetch RM #%s (%s)" % (bug, e))
                continue
            if rm.is_issue_wont_fix_or_release_notes(task):
                t.set_wont_fix()
                tmp = "%s RM #%s: %s" % (task['status']['name'], bug, task['subject'])
                WONT_FIX[name] = tmp
                t.set_skip(tmp)
            elif rm.is_issue_open(task):
                days = rm.updated_days_ago(task)
                tmp = "RM #%s: %s" % (bug, task['subject'])
                if days > 60:
                    tmp = "Open for %s days - %s" % (days, tmp)
                t.set_skip(tmp)
                break
            sys.stdout.write('.')
            sys.stdout.flush()
            print_newline = True

    if print_newline:
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
    if not RM_API_KEY:
        return
    print("Check redmine for open issues")
    rm = MlxRedmine(RM_API_KEY)
    for t in TESTS:
        if t.ignore:
            continue
        data = get_test_header(t.fname)
        name = t.name
        bugs = re.findall(r"#\s*Bug SW #([0-9]+):", data)
        for b in bugs:
            try:
                task = rm.get_issue(b)
            except ConnectionError as e:
                continue
            sys.stdout.write('.')
            sys.stdout.flush()
            if rm.is_issue_open(task):
                t.set_skip("RM #%s: %s" % (b, task['subject']))
                break

        if not t.skip and 'IGNORE_FROM_TEST_ALL' in data:
            t.set_ignore("IGNORE_FROM_TEST_ALL")
    print()


def ignore_excluded(tests, exclude):
    if not exclude:
        return

    for item in exclude[:]:
        if ',' in item:
            exclude.remove(item)
            exclude.extend(item.split(','))

    for item in exclude:
        for t in tests:
            if t.name == item or fnmatch(t.name, item):
                t.set_ignore('excluded')


def get_summary():
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
    runtime = get_total_runtime()
    runtime = human_time_duration(runtime)

    return {'number_of_tests': number_of_tests,
            'passed_tests': passed_tests,
            'failed_tests': failed_tests,
            'skip_tests': skip_tests,
            'ignored_tests': ignored_tests,
            'running': running,
            'pass_rate': pass_rate,
            'runtime': runtime,
            }


def prep_html_results(tests):
    test_results = ''
    for t in tests:
        status = t.status
        if status in ('UNKNOWN', "DIDN'T RUN"):
            status = format_result(status, '', html=True)

        logname = os.path.join(LOGDIR, t.test_log_html)
        if os.path.exists(logname):
            status = "<a href='{test_log}'>{status}</a>".format(
                test_log=t.test_log_html,
                status=status)

        name = t.name
        if t.tag:
            name += t.tag
        test_results += RESULT_ROW.format(test=name, run_time=t.run_time, status=status)

    return test_results


def prep_envinfo():
    global envinfo

    info = ""

    for key in envinfo:
        info += ENV_ROW.format(key=key, val=envinfo[key])

    return info


def save_summary_html():
    if not LOGDIR:
        return

    info = prep_envinfo()

    tmp = get_summary()
    summary = SUMMARY_ROW.format(**tmp)

    results = prep_html_results(TESTS)
    rerun_results = prep_html_results(RERUN_TESTS)
    if rerun_results:
        rerun = RERUN_HTML.format(rerun_results=rerun_results)
    else:
        rerun = ""

    summary_file = os.path.join(LOGDIR, "summary.html")
    with open(summary_file, 'w') as f:
        f.write(HTML.format(style=HTML_CSS, envinfo=info, summary=summary, results=results, rerun=rerun))
    return summary_file


def prepare_logdir():
    global LOGDIR

    if args.dry:
        return
    if args.log_dir:
        logdir = args.log_dir
        os.mkdir(logdir)
    else:
        logdir = mkdtemp(prefix='devtests-')

    print("Log dir: " + logdir)
    LOGDIR = logdir
    os.environ['DEVTESTS_LOGDIR'] = LOGDIR
    os.environ['DEVTESTS_STAMP'] = datetime.now().strftime("%Y_%m_%d_%H_%M_%S")
    return logdir


def get_db_path(db):
    db2 = os.path.join('databases', db)
    db3 = os.path.join(MYDIR, 'databases', db)
    for i in (db, db2, db3):
        if os.path.exists(i):
            return i
    err("Cannot find db %s" % db)


def default_filter_dbs(dbs):
    for db in dbs[:]:
        base = os.path.basename(db)
        if (base.startswith('db_local') or base.startswith('db_remote') or
            base in ('first_db.yaml', 'second_db.yaml', 'ct_db.yaml')):
            continue
        dbs.remove(db)


def get_dbs():
    global DB_PATH

    if len(args.db) == 1 and '*' in args.db[0]:
        dbs = glob(args.db[0]) or glob(os.path.join(MYDIR, 'databases', args.db[0]))
        if os.path.basename(args.db[0]) == '*':
            default_filter_dbs(dbs)
    elif len(args.db) == 1 and os.path.isdir(args.db[0]):
        dbs = glob(args.db[0]+'/*') or glob(os.path.join(MYDIR, 'databases', args.db[0]+'/*'))
        default_filter_dbs(dbs)
    elif len(args.db) == 1 and ',' in args.db[0]:
        dbs = args.db[0].split(',')
    else:
        dbs = args.db

    dbs_out = []
    for db in dbs:
        if 'ignore_db' in db:
            continue
        db = get_db_path(db)
        if not db:
            return {}
        if not DB_PATH:
            DB_PATH = os.path.dirname(db)
        dbs_out.append(db)

    return dbs_out


def read_db(db):
    db = get_db_path(db)
    print("DB: %s" % db)
    with open(db) as yaml_data:
        data = yaml.safe_load(yaml_data)
        print("Description: %s" % data.get("description", "Empty"))
    return data


def read_mini_reg_list():
    global MINI_REG_LIST

    if not DB_PATH:
        return

    minis = glob(os.path.join(DB_PATH, '*mini*.yaml'))
    MINI_REG_LIST = []

    for mini in minis:
        with open(mini) as f:
            data = yaml.safe_load(f)
            if type(data['tests']) is dict:
                MINI_REG_LIST.extend(data['tests'].keys())
            elif type(data['tests']) is list:
                MINI_REG_LIST.extend(data['tests'])


def read_ignore_db():
    global IGNORE_LIST

    if not DB_PATH:
        return

    ignoredb = os.path.join(DB_PATH, 'ignore_db.yaml')
    if not os.path.exists(ignoredb):
        return

    with open(ignoredb) as f:
        data = yaml.safe_load(f)
        if type(data['tests']) is dict:
            IGNORE_LIST = data['tests'].keys()
        elif type(data['tests']) is list:
            IGNORE_LIST = data['tests']
        root_folders = data.get('root_folders', [''])

    return root_folders


def update_opts(opts1, opts2):
    d = {}
    d.update(opts1)
    # ignore is special case. can be dict for one item or a list.
    ignore = d.get('ignore', [])
    if type(ignore) == dict:
        ignore = [ignore]
    d['ignore'] = ignore + []

    if not opts2:
        return d

    for k, v in opts2.items():
        if k == 'ignore':
            # handle special case ignore.
            if type(v) == dict:
                v = [v]
            d[k].extend(v)
        elif type(v) == dict:
            d[k] = d.get(k, {})
            d[k].update(v)
        elif type(v) == list:
            d[k] = d.get(k, []) + v
        else:
            d[k] = v

    return d


def load_tests_from_(data, sub, opts={}, group=''):
    tests = []
    if type(data) != dict:
        return tests
    opts = update_opts(opts, data.get('opts', {}))
    for key in data:
        if fnmatch(key, 'test-*.sh'):
            # Join all keys under test to opts. (no need for opts key).
            test_opts = update_opts(opts, data[key])
            t = Test(os.path.join(MYDIR, sub, key), test_opts)
            t.group = group
            tests.append(t)
        elif key == 'opts':
            continue
        elif os.path.isdir(os.path.join(MYDIR, key)):
            tests.extend(load_tests_from_(data[key], key, opts, group))
        elif data[key]:
            # a group.
            group1 = os.path.join(group, key)
            grp_tests = load_tests_from_(data[key], sub, opts, group1)
            if grp_tests:
                tests.extend(grp_tests)
            else:
                warn("Invalid key %s" % key)
        else:
            # empty group. add a test to get a log and a warning about missing test.
            tests.append(Test(os.path.join(MYDIR, sub, key), opts))
    return tests


def load_tests_from_db(data):
    deprecated_subfolder = data.get('tests_subfolder', '')
    if deprecated_subfolder:
        warn("Using deprecated key 'tests_subfolder'.")
    tests = load_tests_from_(data['tests'], deprecated_subfolder)

    for test in tests:
        if not test.exists():
            warn("Cannot find test %s" % test.name)
            test.set_failed("Cannot find test load")

    return tests


def revert_skip_if_needed():
    if not args.run_skipped:
        return

    skipped = []
    for test in TESTS[:]:
        if test.wont_fix:
            continue
        if test.skip:
            test.unset_skip()
        else:
            TESTS.remove(test)


def get_all_tests(root_folder='', include_subfolders=False):
    recursive = False
    if include_subfolders:
        sub = '**'
        recursive = True
    else:
        sub = ''
    pat = os.path.join(MYDIR, root_folder, sub, 'test-*.sh')
    return glob(pat, recursive=recursive)


def get_tests_from_glob(lst, tests):
    if not lst:
        return []
    tmp = []
    for i in lst:
        g = glob(os.path.join(MYDIR, i))
        for f in g:
            if f in tests:
                continue
            tmp.append(f)
    return [Test(t) for t in tmp]


def get_tests():
    global TESTS

    try:
        get_current_state()

        if args.db:
            TESTS = []
            if RM_API_KEY:
                rm = MlxRedmine(RM_API_KEY)
            else:
                rm = None
            for db in get_dbs():
                data = read_db(db)
                if 'tests' in data:
                    _tests = load_tests_from_db(data)
                    ignore_excluded(_tests, args.exclude)
                    update_skip_according_to_db(rm, _tests, data)
                    TESTS.extend(_tests)
            glob_tests(args.glob)
            read_mini_reg_list()
            revert_skip_if_needed()
        else:
            tmp = get_all_tests()
            _added = get_tests_from_glob(args.glob, tmp)
            TESTS = [Test(t) for t in tmp]
            glob_tests(args.glob)
            TESTS.extend(_added)
            ignore_excluded(TESTS, args.exclude)
            update_skip_according_to_rm()
            revert_skip_if_needed()

        return True
    except RuntimeError as e:
        err("%s" % e)
        return False


def print_test_line(name, reason):
    print("%-62s " % deco(name, 'cyan'), end=' ')
    print("%-30s" % deco(reason, 'yellow'))


def db_check():
    if not RM_API_KEY:
        err('Cannot do db check without a redmine key')
        return 1
    rm = MlxRedmine(RM_API_KEY)
    root_folders = read_ignore_db()
    all_tests = []
    for d in root_folders:
        all_tests.extend(get_all_tests(d, include_subfolders=True))
    all_tests = [os.path.basename(t) for t in all_tests]
    sort_tests(all_tests)

    for test in TESTS:
        if test.name in all_tests:
            all_tests.remove(test.name)

    for test in IGNORE_LIST:
        if test in all_tests:
            all_tests.remove(test)
        elif '*' in test:
            for t in all_tests[:]:
                if fnmatch(t, test):
                    all_tests.remove(t)

    for test in all_tests:
        print_test_line(test, "Missing in db")

    target_version = ''
    for test in TESTS:
        name = test.name
        if test.name in WONT_FIX:
            print_test_line(name, WONT_FIX[name])
            continue
        for task in test.issues:
            if not rm.is_issue_open(task):
                continue

            if rm.is_tracker_bug(task):
                if 'fixed_version' in task:
                    fixed_version = task['fixed_version']['name']
                    if not target_version:
                        target_version = fixed_version
                    elif fixed_version != target_version:
                        print_test_line(name, "Mismatch target versions '%s' vs '%s' (RM #%s)" % (fixed_version, target_version, task['id']))
                else:
                    tmp = "RM #%s: %s" % (task['id'], task['subject'])
                    print_test_line(name, "Missing target version: %s" % tmp)

            days = rm.created_days_ago(task)
            if days > 28:
                tmp = "RM #%s: %s" % (task['id'], task['subject'])
                print_test_line(name, "Over %d days old: %s" % (days, tmp))
    return 0


def pre_quick_status_updates():
    if not args.html or args.dry:
        return

    for test in TESTS:
        res = ''
        reason = ''

        if not test.exists():
            res = 'FAILED'
            reason = 'Cannot find test pre'
            test.set_failed(reason)
        elif test.ignore:
            res = 'IGNORED'
            reason = test.reason
        elif test.skip:
            res = 'SKIP'
            reason = test.reason
        else:
            continue

        test.status = format_result(res, reason, html=True)


def escape_ansi(line):
    ansi_escape = re.compile(r'(?:\x1B[@-_]|[\x80-\x9F])[0-?]*[ -/]*[@-~]')
    return ansi_escape.sub('', line)


def __run_test(test):
    failed = False
    res = ''
    reason = ''
    logname = ''
    total_seconds = 0.0

    name = deco(test.name, 'cyan')
    name += deco(test.tag, TAG_COLOR)
    name_stripped = escape_ansi(name)
    space = COL_TEST_NAME - len(name_stripped)
    __col1 = name + ' ' * space
    print(__col1, end=' ')

    if args.loops > 1:
        print("%-5s" % str(test.iteration+1), end=' ')

    sys.stdout.flush()

    if test.failed:
        failed = True
        res = 'FAILED'
        reason = test.reason
    elif not test.exists():
        # TODO fix multiple places checking test exists "Cannot find test"
        failed = True
        res = 'FAILED'
        reason = 'Cannot find test run'
        test.set_failed(reason)
    elif test.ignore:
        res = 'IGNORED'
        reason = test.reason
    elif test.skip:
        res = 'SKIP'
        reason = test.reason
    else:
        start_time = datetime.now()
        logname = os.path.join(LOGDIR, test.test_log)
        if args.dry:
            test.cmd = "/bin/echo dry-run"
            logname = ''
        try:
            reason = test.run(args.html)
            res = 'TEST PASSED'
            test.set_passed()
            if args.dry:
                res = 'DRY'
                reason = ''
        except ExecCmdFailed as e:
            failed = True
            reason = str(e)
            res = 'FAILED'
            test.set_failed(reason)
        end_time = datetime.now()
        total_seconds = float("%.2f" % (end_time - start_time).total_seconds())

    test.run_time = total_seconds
    total_seconds = "%-7s" % total_seconds
    if test.run_time > 300:
        total_seconds = deco(total_seconds, 'yellow')
    print("%s " % total_seconds, end=' ')

    if (test.name in MINI_REG_LIST) and (test.skip or test.ignore or test.failed):
        res = "%s SHOW STOPPER" % res
    test.status = format_result(res, reason, html=True)
    print("%s %s" % (format_result(res, reason), logname))

    return failed


def copy_test(test, iteration):
    test = copy(test)
    test.iteration = iteration
    test.init_state()
    test.set_logs(test.iteration)
    return test


def run_tests(iteration):
    ignore_from_test = args.from_test is not None
    ignore_to_test = args.to_test is not None
    failed = False
    inject_test = None

    if args.inject_test:
        inject_test = Test(os.path.join(MYDIR, args.inject_test))

    pre_quick_status_updates()

    if iteration == 0:
        __col1 = "Test".ljust(COL_TEST_NAME, ' ')
        if args.loops > 1:
            print("%s %-5s %-8s %s" % (__col1, "Iter", "Time", "Status"))
        else:
            print("%s %-8s %s" % (__col1, "Time", "Status"))

    iter_tests = []
    rerun_tests = []
    group = ""

    for test in TESTS:
        # skip copied tests
        if test.iteration > 0:
            continue

        if ignore_from_test:
            if args.from_test != test.name:
                continue
            ignore_from_test = False

        if iteration > 0:
            # save as a copy for the summary
            test = copy_test(test, iteration)
            iter_tests.append(test)

        # Pre update summary report before running next test.
        # In case we crash we still might want the report.
        test.status = 'UNKNOWN'
        if args.html and not args.dry:
            save_summary_html()

        if args.group and group != test.group:
            print("-- %s --" % test.group)
            group = test.group

        test_failed = __run_test(test)
        failed = failed or test_failed

        if inject_test and not (test.skip or test.ignore) and \
           inject_test.name != test.name:
            test = copy_test(inject_test, 0)
            test.tag = INJECT_TAG
            __run_test(test)

        if test_failed and args.rerun_failed:
            test = copy_test(test, 1)
            rerun_tests.append(test)
            test.tag = RERUN_TAG
            __run_test(test)

        for __env_key in test.opts.get('env', {}):
            if __env_key.lower().startswith('ignore'):
                reason = test.opts['env'][__env_key]
                test = copy_test(test, 0)
                test.tag = '*' + __env_key.lower()
                test.set_ignore(reason)
                iter_tests.append(test)
                __run_test(test)

        if args.stop and failed:
            return 1

        if ignore_to_test and args.to_test == test.name:
            break
    # end test loop

    TESTS.extend(iter_tests)
    RERUN_TESTS.extend(rerun_tests)

    return failed


def calc_test_col_len():
    global COL_TEST_NAME
    rerun_tag_len = len(RERUN_TAG)
    ln = 1
    for t in TESTS:
        if len(t.name) > ln:
            ln = len(t.name) + rerun_tag_len
    if args.inject_test and len(args.inject_test) > ln:
        ln = len(args.inject_test) + rerun_tag_len
    COL_TEST_NAME = ln + 2


def main():
    if not get_tests():
        return 1

    if len(TESTS) == 0:
        err("No tests to run")
        return 1

    prepare_logdir()
    calc_test_col_len()

    if not args.db_check:
        sort_tests(TESTS, args.randomize)

    if args.db_check:
        sort_tests(TESTS)
        return db_check()

    if not args.loops:
        args.loops = 1

    failed = False

    for iteration in range(args.loops):
        failed = failed or run_tests(iteration)

        if args.stop and failed:
            return 1
    # end loops

    if failed:
        return 1

    return 0


def cleanup():
    runtime = get_total_runtime()
    if runtime > 1:
        print("runtime: %s" % human_time_duration(runtime))
    if args.html and not args.dry:
        summary_file = save_summary_html()
        if summary_file:
            print("Summary: %s" % summary_file)


def signal_handler(signum, frame):
    print("\nTerminated")
    cleanup()
    sys.exit(signum)


def get_total_runtime(with_reruns=False):
    all_time = (datetime.now() - test_all_start_time).total_seconds()
    if not with_reruns:
        all_time -= sum(t.run_time for t in RERUN_TESTS)

    return float("%.2f" % all_time)


def get_distro():
    distro = {}
    try:
        with open("/etc/os-release", 'r') as f:
            for line in f.readlines():
                line = line.strip().split('=')
                if line[0]:
                    distro[line[0]] = line[1].strip('"')
    except OSError:
        pass
    return distro


if __name__ == "__main__":
    test_all_start_time = datetime.now()
    args = parse_args()
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    rc = main()
    cleanup()
    sys.exit(rc)
