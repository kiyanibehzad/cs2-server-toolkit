#!/usr/bin/env python3
import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).resolve().parents[1] / "scripts/cs2-buildid.py"
spec = importlib.util.spec_from_file_location("cs2_buildid", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BuildTests(unittest.TestCase):
    def test_public_branch_even_when_other_branch_is_first(self):
        data = '''"730" { "depots" { "branches" {
          "test" { "buildid" "100" }
          "public" { "description" "Public" "buildid" "200" }
        } } }'''
        self.assertEqual(module.public_buildid(data), "200")

    def test_missing_public_branch(self):
        self.assertIsNone(module.public_buildid('"branches" { "test" { "buildid" "100" } }'))


if __name__ == "__main__":
    unittest.main()
