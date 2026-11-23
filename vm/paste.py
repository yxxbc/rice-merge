#!/usr/bin/env python3
"""Type text into a running QEMU guest via QMP (host -> guest clipboard).

Used by vm/paste.sh. Only ASCII is supported: QEMU injects keycodes, and the
live console cannot render CJK anyway.

  python3 vm/paste.py --text "setfont -d" --sock vm/qmp.sock
  pbpaste | python3 vm/paste.py --sock vm/qmp.sock
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import time

# QEMU qcode names for characters that are not simply their own name.
PLAIN = {
    " ": "spc",
    "-": "minus",
    "=": "equal",
    "[": "bracket_left",
    "]": "bracket_right",
    "\\": "backslash",
    ";": "semicolon",
    "'": "apostrophe",
    "`": "grave_accent",
    ",": "comma",
    ".": "dot",
    "/": "slash",
    "\n": "ret",
    "\r": "ret",
    "\t": "tab",
}

SHIFTED = {
    "~": "grave_accent",
    "!": "1",
    "@": "2",
    "#": "3",
    "$": "4",
    "%": "5",
    "^": "6",
    "&": "7",
    "*": "8",
    "(": "9",
    ")": "0",
    "_": "minus",
    "+": "equal",
    "{": "bracket_left",
    "}": "bracket_right",
    "|": "backslash",
    ":": "semicolon",
    '"': "apostrophe",
    "<": "comma",
    ">": "dot",
    "?": "slash",
}


class QMP:
    def __init__(self, path: str):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(10)
        self.sock.connect(path)
        self.file = self.sock.makefile("rwb", buffering=0)
        self.file.readline()  # greeting
        self._cmd({"execute": "qmp_capabilities"})

    def _cmd(self, payload: dict) -> dict:
        self.file.write((json.dumps(payload) + "\n").encode())
        while True:
            line = self.file.readline()
            if not line:
                raise RuntimeError("QMP connection closed")
            reply = json.loads(line)
            if "event" in reply:
                continue
            if "error" in reply:
                raise RuntimeError(reply["error"].get("desc", "QMP error"))
            return reply

    def keys(self, keys: list[str], hold_ms: int = 40) -> None:
        self._cmd(
            {
                "execute": "send-key",
                "arguments": {
                    "keys": [{"type": "qcode", "data": k} for k in keys],
                    "hold-time": hold_ms,
                },
            }
        )


def char_keys(ch: str) -> list[str] | None:
    if "a" <= ch <= "z" or "0" <= ch <= "9":
        return [ch]
    if "A" <= ch <= "Z":
        return ["shift", ch.lower()]
    if ch in SHIFTED:
        return ["shift", SHIFTED[ch]]
    if ch in PLAIN:
        return [PLAIN[ch]]
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sock", default=os.path.join(os.path.dirname(__file__), "qmp.sock"))
    parser.add_argument("--text", help="text to type; default: read stdin")
    parser.add_argument("--clipboard", action="store_true", help="read the host clipboard (pbpaste)")
    parser.add_argument("--enter", dest="enter", action="store_true", default=True)
    parser.add_argument("--no-enter", dest="enter", action="store_false")
    parser.add_argument("--delay", type=float, default=0.012, help="seconds between key events")
    args = parser.parse_args()

    if args.clipboard:
        text = subprocess.run(["pbpaste"], check=True, capture_output=True, text=True).stdout
    elif args.text is not None:
        text = args.text
    elif not sys.stdin.isatty():
        text = sys.stdin.read()
    else:
        parser.error("provide --text, --clipboard, or pipe text on stdin")

    if not os.path.exists(args.sock):
        print("QMP socket not found: %s (is the VM running?)" % args.sock, file=sys.stderr)
        return 1

    qmp = QMP(args.sock)
    skipped = 0
    for ch in text:
        if ch == "\r":
            continue
        keys = char_keys(ch)
        if keys is None:
            skipped += 1
            continue
        qmp.keys(keys)
        time.sleep(0.05 if ch == "\n" else args.delay)

    if args.enter and not text.endswith("\n"):
        qmp.keys(["ret"])

    if skipped:
        print("note: skipped %d non-ASCII character(s)" % skipped, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
