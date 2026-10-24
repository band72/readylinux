#!/usr/bin/env python3
# Pull a helper that install.sh writes with put_file out of its heredoc.
#   python3 tests/embedded.py where-is-my-file > out
#   python3 tests/embedded.py --list
import re
import sys
from pathlib import Path

INSTALL = Path(__file__).resolve().parent.parent / "install.sh"
START = re.compile(r'^\s*put_file "[^"]*/([^"/]+)" <<\'(\w+)\'$')


def helpers():
    found = {}
    lines = INSTALL.read_text().splitlines(keepends=True)
    i = 0
    while i < len(lines):
        m = START.match(lines[i].rstrip("\n"))
        i += 1
        if not m:
            continue
        name, end = m.groups()
        body = []
        while i < len(lines) and lines[i].rstrip("\n") != end:
            body.append(lines[i])
            i += 1
        found[name] = "".join(body)
    return found


def extract(name):
    return helpers()[name]


if __name__ == "__main__":
    if sys.argv[1:] == ["--list"]:
        print("\n".join(helpers()))
    else:
        sys.stdout.write(extract(sys.argv[1]))
