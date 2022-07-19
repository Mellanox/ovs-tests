#!/usr/bin/python

import argparse
import requests
from glob import glob


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', required=True, help='Results url')

    return parser.parse_args()


TAGS = (
    "error",
    "failed",
    "mlx5_cmd_out_err",
    "unreferenced object",
    "backtrace",
    "command not found",
    "invalid handle",
    "No such file or directory",
    "WARNING",
    "XXX",
    "TODO",
    "Killed",
)

expected = {
    "test-eswitch-devlink-reload.sh": ["Warning: mlx5_core: reload while VFs are present is unfavorable."]
}


def expected_line(test, line):
    for e in expected.get(test, []):
        if e in line:
            return True
    return False


def start():
    tests = glob("test-*.sh")
    for test in tests:
        url = args.url+"/artifact/test_logs/"+test+".html"
        r = requests.get(url)
        if not r.ok:
            #print(url)
            #print("ERROR: can't get url: %s" % r.status_code)
            continue
        if r.content.find('TEST PASSED') < 0:
            continue

        for i in TAGS:
            for line in r.content.splitlines():
                if (i.lower() in line.lower()) and not expected_line(test, line):
                    break
            if i.lower() not in line.lower():
                continue
            print("%s    - %s" % (test, i))
            print("  %s" % url)
            break


if __name__ == "__main__":
    args = parse_args()
    try:
        start()
    except KeyboardInterrupt:
        print("break")
