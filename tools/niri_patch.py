#!/usr/bin/env python3
"""niri 桌面合并用的文本变换工具。

每个子命令都是幂等的：重复执行不会产生重复内容，返回码 0 表示"已经是目标状态"。
失败（例如找不到插入锚点）返回 1，调用方据此中止而不是静默继续。

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

# 键位块用起止标记包起来：这样片段内容变化时可以整块替换，而不是"见过 marker 就永不更新"。
BEGIN = "// ==== rice-merge binds begin ===="
END = "// ==== rice-merge binds end ===="
# 0.1 版本写下的旧标记；遇到时把旧片段整段换成新块。
LEGACY = "// ==== low-spec rice ===="
MARKER = BEGIN  # 向后兼容：旧测试/调用方引用这个名字


def _read(path):
    with io.open(path, encoding="utf-8") as handle:
        return handle.read()


def _write(path, text):
    with io.open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def _last_standalone_brace(lines):
    for i in range(len(lines) - 1, -1, -1):
        if lines[i].strip() == "}":
            return i
    return None


def _marker_span(lines):
    """返回 (begin, end) 行号；没有完整块时返回 None。"""
    begin = None
    for i, line in enumerate(lines):
        if line.strip() == BEGIN:
            begin = i
            break
    if begin is None:
        return None
    for j in range(begin + 1, len(lines)):
        if lines[j].strip() == END:
            return begin, j
    return None


def cmd_binds(args):
    """把 rice 键位块放在 binds.kdl 最后一个独占一行的 } 之前。"""
    text = _read(args.file)
    fragment = _read(args.fragment).rstrip("\n")
    if not fragment.strip():
        print("binds: fragment is empty", file=sys.stderr)
        return 1

    block = [BEGIN] + fragment.splitlines() + [END]
    lines = text.splitlines()

    span = _marker_span(lines)
    if span is not None:
        begin, end = span
        if lines[begin : end + 1] == block:
            print("binds: already applied")
            return 0
        lines[begin : end + 1] = block
        _write(args.file, "\n".join(lines) + "\n")
        print("binds: updated in place")
        return 0

    # 旧版本只写了 marker + 片段：删掉 marker 到最后一个 } 之间的内容
    legacy_at = next((i for i, line in enumerate(lines) if line.strip() == LEGACY), None)
    brace = _last_standalone_brace(lines)
    if brace is None:
        print("binds: no standalone closing brace in %s" % args.file, file=sys.stderr)
        return 1
    if legacy_at is not None and legacy_at < brace:
        del lines[legacy_at:brace]
        brace = _last_standalone_brace(lines)

    insert_at = _last_standalone_brace(lines)
    if insert_at is None:
        print("binds: no standalone closing brace in %s" % args.file, file=sys.stderr)
        return 1
    lines[insert_at:insert_at] = block
    _write(args.file, "\n".join(lines) + "\n")
    print("binds: inserted")
    return 0


def cmd_include(args):
    """在 config.kdl 的 --after 那一行 include 后面插入一行 include。"""
    lines = _read(args.file).splitlines()
    wanted = 'include "%s"' % args.name
    if any(line.strip() == wanted for line in lines):
        print("include: already present")
        return 0

    anchor = 'include "%s"' % args.after
    index = next((i for i, line in enumerate(lines) if line.strip() == anchor), None)
    if index is None:
        # 只按整行匹配，避免命中注释里的 include
        print("include: anchor %r not found in %s" % (anchor, args.file), file=sys.stderr)
        return 1
    lines.insert(index + 1, wanted)
    _write(args.file, "\n".join(lines) + "\n")
    print("include: added")
    return 0


def cmd_matugen(args):
    """删掉不需要的 [templates.X] 段（matugen 会覆盖 shorin 的 foot/mako/fuzzel 配置）。"""
    text = _read(args.file)
    before = text
    for name in args.section:
        text = re.sub(
            r"(?m)^\[templates\.%s\][^\n]*\n(?:.*?\n)*?(?=^\[|\Z)"
            % re.escape(name),
            "",
            text,
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
    count = text.count(args.old)
    if count == 0:
        print("sub: pattern not found, skipped")
        return 0
    _write(args.file, text.replace(args.old, args.new))
    print("sub: replaced %d occurrence(s)" % count)
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
