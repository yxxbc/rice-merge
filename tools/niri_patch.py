#!/usr/bin/env python3
"""niri 桌面合并用的文本变换工具。

每个子命令都是幂等的：重复执行不会产生重复内容，返回码 0 表示"已经是目标状态"。
失败（例如找不到插入锚点）返回 1，调用方据此告警而不是静默继续。

用法：
  niri_patch.py binds   <binds.kdl>    <fragment.kdl>
  niri_patch.py include <config.kdl>   --name rice-colors.kdl --after layout.kdl
  niri_patch.py matugen <config.toml>  --section foot --section mako
  niri_patch.py sub     <file>         --old /home/yg --new /home/me
"""

from __future__ import annotations

import argparse
import io
import re
import sys

MARKER = "// ==== low-spec rice ===="


def _read(path):
    with io.open(path, encoding="utf-8") as handle:
        return handle.read()


def _write(path, text):
    with io.open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def cmd_binds(args):
    """把 rice 键位插到 binds.kdl 最后一个独占一行的 } 之前。"""
    text = _read(args.file)
    if MARKER in text:
        print("binds: already applied")
        return 0
    fragment = _read(args.fragment).rstrip("\n")
    if not fragment:
        print("binds: fragment is empty", file=sys.stderr)
        return 1
    lines = text.splitlines(keepends=True)
    line_no = next((i for i in range(len(lines) - 1, -1, -1) if lines[i].strip() == "}"), None)
    if line_no is None:
        print("binds: no standalone closing brace in %s" % args.file, file=sys.stderr)
        return 1
    offset = sum(len(line) for line in lines[:line_no])
    _write(args.file, text[:offset] + "    " + MARKER + "\n" + fragment + "\n" + text[offset:])
    print("binds: inserted")
    return 0


def cmd_include(args):
    """在 config.kdl 的 --after 那一行后面插入 include。"""
    text = _read(args.file)
    line = 'include "%s"' % args.name
    if line in text:
        print("include: already present")
        return 0
    anchor = 'include "%s"' % args.after
    if anchor not in text:
        print("include: anchor %r not found in %s" % (anchor, args.file), file=sys.stderr)
        return 1
    _write(args.file, text.replace(anchor, anchor + "\n" + line, 1))
    print("include: added")
    return 0


def cmd_matugen(args):
    """删掉不需要的 [templates.X] 段（matugen 会覆盖 shorin 的 foot/mako/fuzzel 配置）。"""
    text = _read(args.file)
    before = text
    for name in args.section:
        text = re.sub(
            r"\[templates\.%s\].*?(?=\n\[|\Z)" % re.escape(name), "", text, flags=re.S
        )
    if text == before:
        print("matugen: nothing to do")
        return 0
    _write(args.file, text.rstrip("\n") + "\n")
    print("matugen: trimmed (%s)" % ", ".join(args.section))
    return 0


def cmd_sub(args):
    """纯文本替换；找不到原串时视为已满足。"""
    text = _read(args.file)
    if args.old not in text:
        print("sub: pattern not found, skipped")
        return 0
    _write(args.file, text.replace(args.old, args.new))
    print("sub: replaced")
    return 0


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("binds", help="把键位片段插入 binds.kdl")
    p.add_argument("file")
    p.add_argument("fragment")
    p.set_defaults(func=cmd_binds)

    p = sub.add_parser("include", help="给 niri config.kdl 加一行 include")
    p.add_argument("file")
    p.add_argument("--name", required=True, help='要 include 的文件名，如 rice-colors.kdl')
    p.add_argument("--after", required=True, help='插在哪一行 include 之后，如 layout.kdl')
    p.set_defaults(func=cmd_include)

    p = sub.add_parser("matugen", help="删除 matugen 配置里的模板段")
    p.add_argument("file")
    p.add_argument("--section", action="append", required=True, help="要删除的模板名，可重复")
    p.set_defaults(func=cmd_matugen)

    p = sub.add_parser("sub", help="纯文本替换")
    p.add_argument("file")
    p.add_argument("--old", required=True)
    p.add_argument("--new", required=True)
    p.set_defaults(func=cmd_sub)

    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
