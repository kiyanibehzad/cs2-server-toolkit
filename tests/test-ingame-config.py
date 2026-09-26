#!/usr/bin/env python3
"""Check admin edits preserve other permissions and loader repair is safe to repeat."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/cs2-ingame-config.py"
OWNER = "76561198000000000"
SECOND = "76561198000000001"


class IngameConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_tool(self, *args, success=True):
        result = subprocess.run([sys.executable, str(SCRIPT), *map(str, args)], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return result.stdout

    def test_admin_management_preserves_other_admins_and_flags(self):
        path = self.root / "admins.json"
        path.write_text(json.dumps({"Another plugin": {"identity": OWNER, "flags": ["@css/generic"]},
                                    "Other person": {"identity": SECOND, "flags": ["@css/kick"]}}))
        self.run_tool("admin-add", path, OWNER, "Behzad")
        self.run_tool("admin-add", path, OWNER, "Behzad")
        data = json.loads(path.read_text())
        self.assertEqual(data["Another plugin"]["flags"], ["@css/generic", "@cs2toolkit/admin"])
        self.assertIn("Other person", data)
        self.assertEqual(self.run_tool("admin-list", path).strip(), f"{OWNER}  Another plugin")
        self.run_tool("admin-remove", path, OWNER)
        data = json.loads(path.read_text())
        self.assertEqual(data["Another plugin"]["flags"], ["@css/generic"])
        self.assertIn("Other person", data)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.run_tool("admin-add", path, "123;quit", success=False)

    def test_loader_moves_line_first_and_is_idempotent(self):
        path = self.root / "gameinfo.gi"
        path.write_text('"GameInfo"\n{\n\tFileSystem\n\t{\n\t\tSearchPaths\n\t\t{\n\t\t\tGame csgo\n\t\t\tGame csgo/addons/metamod\n\t\t\tGame core\n\t\t}\n\t}\n}\n')
        self.run_tool("repair-loader", path)
        first = path.read_text()
        self.assertEqual(first.count("Game csgo/addons/metamod"), 1)
        self.assertLess(first.index("Game csgo/addons/metamod"), first.index("Game csgo\n"))
        self.run_tool("repair-loader", path)
        self.assertEqual(path.read_text(), first)


if __name__ == "__main__":
    unittest.main()
