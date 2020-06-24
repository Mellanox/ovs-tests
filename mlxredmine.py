#!/usr/bin/python

import requests
from requests.packages.urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

REDMINE_URL = 'http://redmine.mellanox.com'
API_KEY = "1c438dfd8cf008a527ad72f01bd5e1bac24deca5"

# redmine status codes
STATUS_IN_PROGRESS = 2
STATUS_FIXED = 16
STATUS_RELEASE_NOTES = 14
STATUS_WONT_FIX = 11
STATUS_REJECTED = 6
STATUS_CLOSED = 5
STATUS_CLOSED_REJECTED = 38


class MlxRedmine(object):
    def get_url(self, url, params=None):
        headers = {
            'X-Redmine-API-Key': API_KEY
        }
        return requests.get(url, headers=headers, params=params, verify=False)

    def get_issue(self, issue_id):
        r = self.get_url(REDMINE_URL + '/issues/%s.json' % issue_id)
        j = r.json()
        task = j['issue']
        return task

    def is_issue_wont_fix_or_release_notes(self, task):
        return task['status']['id'] in (STATUS_WONT_FIX, STATUS_RELEASE_NOTES)

    def is_issue_closed(self, task):
        return task['status']['id'] in (STATUS_FIXED, STATUS_CLOSED, STATUS_CLOSED_REJECTED)

    def is_issue_open(self, task):
        return not self.is_issue_closed(task)
