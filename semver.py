#!/usr/bin/python

import re


def tryint(i):
    try:
        return int(i)
    except ValueError:
        return i


class VersionInfo(object):
    def __init__(self, version):
        self.version = str(version)
        self.plus = self.version[-1] == '+'
        stripped_version = self.version.strip('+')
        s = re.sub('[.-]', ' ', stripped_version).split()
        # Quick WA to avoid split errors for short versions
        s += [0, 0, 0, 0]
        self.major = tryint(s[0])
        self.minor = tryint(s[1])
        self.patch = tryint(s[2])
        self.build = tryint(s[3])
        # rc tags appear in the patch part
        self.rc = None
        if 'rc' in str(self.patch):
            self.rc = int(self.patch.strip('rc'))
            self.patch = 0

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
        if self.patch < other.patch:
            return True
        if self.patch > other.patch:
            return False
        if self.build < other.build:
            return True
        if self.build > other.build:
            return False
        # without rc consider stable and its a newer version
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
