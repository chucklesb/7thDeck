#!/usr/bin/env python3
"""Sets values in a Wine registry file (user.reg, system.reg) without starting Wine.

    regedit.py FILE KEY NAME VALUE [KEY NAME VALUE ...]

KEY is relative to the file's root, with single backslashes (Software\\Wine\\DllOverrides).
VALUE is str:TEXT or dword:NUMBER. The prefix's wineserver must not be running: it rewrites the
file from memory when it exits.
"""
import os
import re
import sys
import time

HEADER = re.compile(r"^\[(.*)\](?:\s+\d+)?\s*$")


def unescape(text):
    return re.sub(r"\\(.)", r"\1", text)


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def render(value):
    kind, _, data = value.partition(":")
    if kind == "str":
        return '"%s"' % escape(data)
    if kind == "dword":
        return "dword:%08x" % (int(data, 0) & 0xFFFFFFFF)
    raise ValueError("unsupported value %r (use str:TEXT or dword:NUMBER)" % value)


def value_name(line):
    """The unescaped value name a value line sets, or None."""
    if line.startswith("@="):
        return "@"
    m = re.match(r'^"((?:[^"\\]|\\.)*)"=', line)
    return unescape(m.group(1)) if m else None


def section_bounds(lines, key):
    """(header index, end index) of KEY's section, or None."""
    wanted = key.lower()
    for i, line in enumerate(lines):
        m = HEADER.match(line)
        if m and unescape(m.group(1)).lower() == wanted:
            end = i + 1
            while end < len(lines) and not lines[end].startswith("["):
                end += 1
            return i, end
    return None


def set_value(lines, key, name, value):
    line = '%s=%s' % ('@' if name == "@" else '"%s"' % escape(name), render(value))
    bounds = section_bounds(lines, key)
    if bounds is None:
        now = int(time.time())
        filetime = (now + 11644473600) * 10 ** 7
        if lines and lines[-1].strip():
            lines.append("")
        lines += ["[%s] %d" % (escape(key), now), "#time=%x" % filetime, line, ""]
        return
    start, end = bounds
    i = start + 1
    while i < end:
        if (value_name(lines[i]) or "").lower() == name.lower():
            stop = i + 1
            while lines[stop - 1].endswith("\\") and stop < end:
                stop += 1
            lines[i:stop] = [line]
            return
        i += 1
    insert = end
    while insert > start + 1 and not lines[insert - 1].strip():
        insert -= 1
    lines.insert(insert, line)


def main(argv):
    if len(argv) < 4 or (len(argv) - 1) % 3:
        print(__doc__, file=sys.stderr)
        return 2
    path = argv[0]
    with open(path, encoding="utf-8", errors="surrogateescape") as f:
        text = f.read()
    if not text.startswith("WINE REGISTRY"):
        print("regedit.py: %s is not a Wine registry file" % path, file=sys.stderr)
        return 1
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    for i in range(1, len(argv), 3):
        set_value(lines, argv[i], argv[i + 1], argv[i + 2])
    tmp = path + ".%s.tmp" % os.getpid()
    with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
