#!/usr/bin/python

import os
import subprocess
from glob import glob

MYNAME = os.path.basename(__file__)
MYDIR = os.path.abspath(os.path.dirname(__file__))

tests = sorted(glob(MYDIR + '/test-*'))
ignore = [MYNAME]
skip = []



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


for test in tests:
    name = os.path.basename(test)
    if name in ignore:
        continue
    print "Execute test: %s" % name
    if name in skip:
        res = deco("SKIP", 'yellow')
    else:
        res = deco("OK", 'green')
        try:
            run(test)
        except ExecCmdFailed, e:
            res = deco(str(e), 'red')
    print "Result: %s" % res
