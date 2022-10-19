#!/usr/bin/python

import re


def tryint(i):
    try:
        return int(i)
    except ValueError:
        return i


def lt(a, b):
    if type(a) is str or type(b) is str:
        a = str(a)
        b = str(b)
    return a < b


def gt(a, b):
    if type(a) is str or type(b) is str:
        a = str(a)
        b = str(b)
    return a > b


class VersionInfo(object):
    def __init__(self, version):
        self.version = str(version)
        self.plus = self.version[-1] == '+'
        stripped_version = self.version.strip('+')
        s = re.sub('[.-]', ' ', stripped_version).split()
        # Quick WA to avoid split errors for short versions.
        s += [0, 0, 0, 0]
        self.major = tryint(s[0])
        self.minor = tryint(s[1])
        self.patch = tryint(s[2])
        self.build = tryint(s[3])

        # rc tags appear in the build part.
        # e.g. 5.17.0-rc6
        #      6.1.0-rc1_for_upstream_min_debug_2022_10_18_15_06
        self.extra = ''
        if '_' in str(self.build):
            i = self.build.index('_')
            self.extra = self.build[i+1:]
            self.build = self.build[:i]

        self.rc = 0
        if 'rc' in str(self.build):
            self.rc = int(self.build.strip('rc'))
            self.build = 0

    def __gt__(self, other):
        raise RuntimeError("not supported")

    def __eq__(self, other):
        return self.version == other.version

    def __lt__(self, other):
        if self.major < other.major:
            return True
        if self.major > other.major:
            return False
        if self.minor < other.minor:
            return True
        if self.minor > other.minor:
            return False
        if lt(self.patch, other.patch):
            return True
        if gt(self.patch, other.patch):
            return False
        if lt(self.build, other.build):
            return True
        if gt(self.build, other.build):
            return False
        # without rc consider stable and its a newer version
        # e.g. 5.17.0-rc1 < 5.17.0-rc2 < 5.17.0
        if self.rc and not other.rc:
            return True
        if not self.rc and other.rc:
            return False
        if self.rc < other.rc:
            return True
        if self.rc > other.rc:
            return False
        # missing checks?
        # consider equal, so not lt.
        return False

    def __str__(self):
        return "<%s>" % self.version
