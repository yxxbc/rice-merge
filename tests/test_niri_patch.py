#!/usr/bin/env python3
"""niri_patch.py 的行为测试。运行：python3 -m unittest discover -s tests -v"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))

import niri_patch  # noqa: E402

BINDS_SAMPLE = """// niri binds
binds {
    Mod+T { spawn "foot"; }
    Mod+Q { close-window; }
}
"""

FRAGMENT_SAMPLE = """    // rice
    Mod+Y { spawn "rice-paper"; }
    Mod+Ctrl+Y { spawn "theme-selector.sh"; }
"""

CONFIG_SAMPLE = """config-notification {
    disable-failed
}

include "binds.kdl"
include "layout.kdl"
include "output.kdl"

input {
}
"""

MATUGEN_SAMPLE = """[config]
reload_apps = false

[templates.waybar]
output_path = 'x'

[templates.foot]
output_path = 'y'

[templates.mako]
output_path = 'z'

[templates.gtk3]
output_path = 'w'
"""


class Temp:
    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix="niri-patch-")

    def file(self, name, text):
        path = os.path.join(self.dir, name)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return path

    def read(self, path):
        with open(path, encoding="utf-8") as handle:
            return handle.read()


class BindsTests(unittest.TestCase):
    def test_inserts_before_last_brace_and_keeps_balance(self):
        tmp = Temp()
        binds = tmp.file("binds.kdl", BINDS_SAMPLE)
        frag = tmp.file("frag.kdl", FRAGMENT_SAMPLE)
        self.assertEqual(niri_patch.main(["binds", binds, frag]), 0)
        text = tmp.read(binds)
        self.assertEqual(text.count(niri_patch.BEGIN), 1)
        self.assertEqual(text.count(niri_patch.END), 1)
        self.assertEqual(text.count("{"), text.count("}"))
        self.assertIn('Mod+Y { spawn "rice-paper"; }', text)
        self.assertTrue(text.rstrip().endswith("}"))
        # 块必须在最后一个 } 之前
        self.assertLess(text.index(niri_patch.BEGIN), text.rindex("}"))

    def test_is_idempotent(self):
        tmp = Temp()
        binds = tmp.file("binds.kdl", BINDS_SAMPLE)
        frag = tmp.file("frag.kdl", FRAGMENT_SAMPLE)
        niri_patch.main(["binds", binds, frag])
        first = tmp.read(binds)
        niri_patch.main(["binds", binds, frag])
        self.assertEqual(tmp.read(binds), first)

    def test_updates_fragment_in_place(self):
        tmp = Temp()
        binds = tmp.file("binds.kdl", BINDS_SAMPLE)
        frag = tmp.file("frag.kdl", FRAGMENT_SAMPLE)
        niri_patch.main(["binds", binds, frag])
        frag2 = tmp.file("frag2.kdl", '    Mod+Y { spawn "rice-paper"; }\n')
        self.assertEqual(niri_patch.main(["binds", binds, frag2]), 0)
        text = tmp.read(binds)
        self.assertNotIn("theme-selector.sh", text)
        self.assertEqual(text.count(niri_patch.BEGIN), 1)
        self.assertEqual(text.count("{"), text.count("}"))

    def test_migrates_legacy_marker(self):
        tmp = Temp()
        text = (
            "// niri binds\n"
            "binds {\n"
            '    Mod+T { spawn "foot"; }\n'
            '    Mod+Q { close-window; }\n'
            "    // ==== low-spec rice ====\n"
            '    Mod+Y { spawn "rice-paper"; }\n'
            "}\n"
        )
        binds = tmp.file("binds.kdl", text)
        frag = tmp.file("frag.kdl", FRAGMENT_SAMPLE)
        self.assertEqual(niri_patch.main(["binds", binds, frag]), 0)
        out = tmp.read(binds)
        self.assertNotIn(niri_patch.LEGACY, out)
        self.assertEqual(out.count("rice-paper"), 1)
        self.assertEqual(out.count("{"), out.count("}"))

    def test_skips_duplicate_keybind(self):
        tmp = Temp()
        binds = tmp.file("binds.kdl", BINDS_SAMPLE)
        frag = tmp.file(
            "frag.kdl",
            '    Mod+Q { close-window; }\n    Mod+Y { spawn "rice-paper"; }\n',
        )
        self.assertEqual(niri_patch.main(["binds", binds, frag]), 0)
        text = tmp.read(binds)
        self.assertEqual(text.count("Mod+Q"), 1)
        self.assertEqual(text.count("Mod+Y"), 1)
        self.assertEqual(text.count("{"), text.count("}"))

    def test_all_duplicates_is_noop(self):
        tmp = Temp()
        binds = tmp.file("binds.kdl", BINDS_SAMPLE)
        frag = tmp.file("frag.kdl", '    Mod+Q { close-window; }\n')
        before = tmp.read(binds)
        self.assertEqual(niri_patch.main(["binds", binds, frag]), 0)
        self.assertEqual(tmp.read(binds), before)

    def test_fails_without_closing_brace(self):
        tmp = Temp()
        binds = tmp.file("binds.kdl", 'binds {\n    Mod+T { spawn "foot"; }\n')
        frag = tmp.file("frag.kdl", FRAGMENT_SAMPLE)
        self.assertEqual(niri_patch.main(["binds", binds, frag]), 1)


class IncludeTests(unittest.TestCase):
    def test_inserts_after_anchor(self):
        tmp = Temp()
        cfg = tmp.file("config.kdl", CONFIG_SAMPLE)
        rc = niri_patch.main(["include", cfg, "--name", "rice-colors.kdl", "--after", "layout.kdl"])
        self.assertEqual(rc, 0)
        lines = tmp.read(cfg).splitlines()
        self.assertEqual(lines[lines.index('include "layout.kdl"') + 1], 'include "rice-colors.kdl"')

    def test_idempotent_and_anchor_missing(self):
        tmp = Temp()
        cfg = tmp.file("config.kdl", CONFIG_SAMPLE)
        niri_patch.main(["include", cfg, "--name", "rice-colors.kdl", "--after", "layout.kdl"])
        before = tmp.read(cfg)
        niri_patch.main(["include", cfg, "--name", "rice-colors.kdl", "--after", "layout.kdl"])
        self.assertEqual(tmp.read(cfg), before)

        other = tmp.file("config2.kdl", "input {\n}\n")
        self.assertEqual(
            niri_patch.main(["include", other, "--name", "x.kdl", "--after", "layout.kdl"]), 1
        )

    def test_ignores_anchor_inside_comment(self):
        tmp = Temp()
        cfg = tmp.file("config.kdl", "// include \"layout.kdl\"\ninclude \"binds.kdl\"\n")
        self.assertEqual(
            niri_patch.main(["include", cfg, "--name", "x.kdl", "--after", "layout.kdl"]), 1
        )
        out = tmp.read(cfg)
        self.assertNotIn('include "x.kdl"', out)


class MatugenTests(unittest.TestCase):
    def test_removes_only_requested_sections(self):
        tmp = Temp()
        cfg = tmp.file("config.toml", MATUGEN_SAMPLE)
        rc = niri_patch.main(["matugen", cfg, "--section", "foot", "--section", "mako"])
        self.assertEqual(rc, 0)
        text = tmp.read(cfg)
        self.assertNotIn("[templates.foot]", text)
        self.assertNotIn("[templates.mako]", text)
        for kept in ("waybar", "gtk3", "config"):
            self.assertIn(kept, text)

    def test_idempotent(self):
        tmp = Temp()
        cfg = tmp.file("config.toml", MATUGEN_SAMPLE)
        niri_patch.main(["matugen", cfg, "--section", "foot"])
        first = tmp.read(cfg)
        niri_patch.main(["matugen", cfg, "--section", "foot"])
        self.assertEqual(tmp.read(cfg), first)


class SubTests(unittest.TestCase):
    def test_replaces_and_skips_missing(self):
        tmp = Temp()
        f = tmp.file("config.jsonc", 'spawn "waybar" "-c" "/home/yg/.config/waybar/config.jsonc"')
        self.assertEqual(niri_patch.main(["sub", f, "--old", "/home/yg", "--new", "/home/x"]), 0)
        self.assertNotIn("/home/yg", tmp.read(f))
        self.assertIn("/home/x", tmp.read(f))
        self.assertEqual(niri_patch.main(["sub", f, "--old", "/nope", "--new", "/x"]), 0)


if __name__ == "__main__":
    unittest.main()
