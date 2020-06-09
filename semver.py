#!/usr/bin/python

class VersionInfo(object):
    def __init__(self, version):
        self.version = str(version)
        # Quick WA to avoid split errors for short versions
        v = self.version + '.0.0.0'
        s = v.split('.')
        self.major = s[0]
        self.minor = s[1]
        self.patch = s[2]
        self.build = '.'.join(s[3:])

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
        raise RuntimeError("not supported")

    def __str__(self):
        return "<%s>" % self.version
