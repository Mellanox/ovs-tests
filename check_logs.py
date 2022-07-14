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
)


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

        content = r.content.lower()
        for i in TAGS:
            a = content.find(i.lower())
            if a < 0:
                continue
            print("%s    - %s" % (test, i))
            print("  %s" % url)
            #b = content.find("\n", a)
            #a = content.rfind("\n", a)
            #print(a,b)
            #print(content[a:b])
            break


if __name__ == "__main__":
    args = parse_args()
    try:
        start()
    except KeyboardInterrupt:
        print("break")
