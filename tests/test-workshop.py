#!/usr/bin/env python3
"""Offline checks for the public Steam collection adapter."""

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "cs2-workshop.py"
SPEC = importlib.util.spec_from_file_location("cs2_workshop", SCRIPT)
workshop = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(workshop)


class WorkshopTests(unittest.TestCase):
    def test_collection_link_validation(self):
        self.assertEqual(workshop.published_id("https://steamcommunity.com/sharedfiles/filedetails/?id=3455001151"), "3455001151")
        self.assertEqual(workshop.published_id("3455001151"), "3455001151")
        for value in ("https://example.com/sharedfiles/filedetails/?id=123", "123;quit", "0", "http://steamcommunity.com/sharedfiles/filedetails/?id=123"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                workshop.published_id(value)

    def test_fetch_filters_other_apps_and_non_maps(self):
        def fake_post(method, fields):
            if method == "GetCollectionDetails":
                return {"collectiondetails": [{"publishedfileid": "123", "result": 1,
                        "children": [{"publishedfileid": str(i), "filetype": 0} for i in (1, 2, 3)]}]}
            return {"publishedfiledetails": [
                {"publishedfileid": "1", "result": 1, "consumer_app_id": 730, "title": "awp_india\x1b[31m", "tags": [{"tag": "Map"}]},
                {"publishedfileid": "2", "result": 1, "consumer_app_id": 730, "title": "AWP skin", "tags": [{"tag": "Weapon Finish"}]},
                {"publishedfileid": "3", "result": 1, "consumer_app_id": 440, "title": "Other game", "tags": [{"tag": "Map"}]},
            ]}
        with patch.object(workshop, "post_api", side_effect=fake_post):
            self.assertEqual(workshop.fetch_collection("123"), [{"id": "1", "title": "awp_india"}])

    def test_state_keeps_preset_and_rejects_missing_map(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(workshop, "STATE", Path(directory) / "workshop.json"):
            state = workshop.load_state()
            state.update(collection_id="123", maps=[{"id": "1", "title": "awp_india"}], profiles={"1": "scout"})
            workshop.save_state(state)
            self.assertEqual(workshop.load_state()["profiles"]["1"], "scout")
            self.assertEqual(workshop.find_map(workshop.load_state(), "1")["title"], "awp_india")
            with self.assertRaises(ValueError):
                workshop.find_map(workshop.load_state(), "2")
            self.assertEqual(os.stat(workshop.STATE).st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
