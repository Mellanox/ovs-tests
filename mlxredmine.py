#!/usr/bin/python

import requests
from datetime import datetime
from requests.packages.urllib3.exceptions import InsecureRequestWarning
from requests.exceptions import ConnectionError

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

REDMINE_URL = 'http://redmine.mellanox.com'
API_KEY = "1c438dfd8cf008a527ad72f01bd5e1bac24deca5"

# tracker ids
TRACKER_BUG_SW = 28

# redmine status codes
STATUS_IN_PROGRESS = 2
STATUS_FIXED = 16
STATUS_RELEASE_NOTES = 14
STATUS_WONT_FIX = 11
STATUS_REJECTED = 6
STATUS_CLOSED = 5
STATUS_CLOSED_REJECTED = 38
STATUS_CLOSED_EXTERNAL = 74

REDMINE_TIMESTAMP_FMT = '%Y-%m-%dT%H:%M:%S'


def parse_redmine_time(value):
    parts = value.split('.')
    return datetime.strptime(parts[0], REDMINE_TIMESTAMP_FMT)


class MlxRedmine(object):
    def get_url(self, url, params=None):
        headers = {
            'X-Redmine-API-Key': API_KEY
        }
        return requests.get(url, headers=headers, params=params, verify=False)

    def get_issue(self, issue_id, retry=0):
        loops = max(1, retry + 1)

        for i in range(loops):
            try:
                r = self.get_url(REDMINE_URL + '/issues/%s.json' % issue_id)
                break
            except ConnectionError:
                if i+1 == loops:
                    raise
                continue

        j = r.json()
        task = j['issue']
        return task

    def is_issue_wont_fix_or_release_notes(self, task):
        return task['status']['id'] in (STATUS_WONT_FIX, STATUS_RELEASE_NOTES)

    def is_issue_closed(self, task):
        return task['status']['id'] in (STATUS_FIXED, STATUS_CLOSED, STATUS_CLOSED_REJECTED, STATUS_CLOSED_EXTERNAL)

    def is_issue_open(self, task):
        return not self.is_issue_closed(task)

    def is_tracker_bug(self, task):
        return task['tracker']['id'] == TRACKER_BUG_SW

    def created_days_ago(self, task):
        created = parse_redmine_time(task['created_on'])
        return (datetime.now() - created).days

    def updated_days_ago(self, task):
        updated = parse_redmine_time(task['updated_on'])
        return (datetime.now() - updated).days
