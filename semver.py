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
        s = re.sub('[.-]', ' ', self.version).split()
        # Quick WA to avoid split errors for short versions
        s += [0, 0, 0, 0]
        self.major = tryint(s[0])
        self.minor = tryint(s[1])
        self.patch = tryint(s[2])
        self.build = tryint(s[3])

    def __gt__(self, other):
        raise RuntimeError("not supported")

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
        raise RuntimeError("not supported")

    def __str__(self):
        return "<%s>" % self.version
