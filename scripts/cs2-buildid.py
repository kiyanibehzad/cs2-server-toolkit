#!/usr/bin/env python3
"""Read the public-branch build ID from SteamCMD app_info_print VDF."""
import re
import sys


def public_buildid(data):
    # SteamCMD prints a short preamble followed by Valve's quoted KeyValues.
    tokens = re.findall(r'"((?:\\.|[^"\\])*)"|([{}])', data)
    path = []
    key = None
    for quoted, brace in tokens:
        if brace == "{":
            if key is not None:
                path.append(key)
                key = None
        elif brace == "}":
            if path:
                path.pop()
            key = None
        elif key is None:
            key = quoted
        else:
            if len(path) >= 2 and path[-2:] == ["branches", "public"] and key == "buildid":
                if quoted.isdecimal():
                    return quoted
                return None
            key = None
    return None


if __name__ == "__main__":
    build = public_buildid(sys.stdin.read())
    if not build:
        print("public Steam build ID unavailable", file=sys.stderr)
        sys.exit(1)
    print(build)
