#!/usr/bin/env python3
"""Manage CS2 Workshop maps, optional public collections, and map presets."""

import argparse
import json
import os
import re
import sys
import tempfile
import unicodedata
import urllib.parse
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.steampowered.com/ISteamRemoteStorage"
STATE = Path(os.environ.get("CS2_DIR", str(Path.home() / "cs2-ds"))) / "toolkit-config" / "workshop.json"
PROFILES = ("competitive", "awp", "scout")


def fail(message):
    raise ValueError(message)


def published_id(value):
    value = value.strip()
    if value.isascii() and value.isdecimal() and 1 <= len(value) <= 20 and int(value):
        return value
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme != "https" or parsed.hostname not in {"steamcommunity.com", "www.steamcommunity.com"}:
        fail("Use a Steam Community HTTPS Workshop link or a numeric ID.")
    if parsed.path != "/sharedfiles/filedetails/":
        fail("This is not a Steam Workshop item link.")
    ids = urllib.parse.parse_qs(parsed.query).get("id", [])
    if len(ids) != 1:
        fail("The Workshop link must contain one id parameter.")
    return published_id(ids[0])


def post_api(method, fields):
    data = urllib.parse.urlencode(fields).encode("ascii")
    request = urllib.request.Request(f"{API}/{method}/v1/", data=data)
    with urllib.request.urlopen(request, timeout=20) as response:
        if response.status != 200:
            fail(f"Steam API returned HTTP {response.status}.")
        return json.load(response)["response"]


def map_entry(item):
    tags = {str(tag.get("tag", "")).casefold() for tag in item.get("tags", [])}
    if item.get("result") != 1 or item.get("consumer_app_id") != 730 or "map" not in tags:
        return None
    item_id = str(item.get("publishedfileid", ""))
    if not item_id.isdigit() or not int(item_id):
        return None
    raw_title = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", str(item.get("title", "")))
    clean = "".join(char for char in raw_title
                    if not unicodedata.category(char).startswith("C"))
    title = " ".join(clean.split())[:100] or f"Workshop map {item_id}"
    return {"id": item_id, "title": title}


def fetch_map(item_id):
    response = post_api("GetPublishedFileDetails", {
        "itemcount": 1, "publishedfileids[0]": item_id,
    })
    details = response.get("publishedfiledetails", [])
    entry = map_entry(details[0]) if details else None
    if not entry or entry["id"] != item_id:
        fail("Workshop item is unavailable or is not a CS2 map.")
    return entry


def fetch_collection(collection_id):
    response = post_api("GetCollectionDetails", {
        "collectioncount": 1,
        "publishedfileids[0]": collection_id,
    })
    details = response.get("collectiondetails", [])
    if not details or str(details[0].get("publishedfileid")) != collection_id or details[0].get("result") != 1:
        fail("Collection is unavailable. Check its ID and visibility in Steam.")
    children = details[0].get("children", [])
    ids = list(dict.fromkeys(str(child.get("publishedfileid")) for child in children
                             if child.get("filetype") == 0 and str(child.get("publishedfileid", "")).isdigit()))
    if len(ids) > 500:
        fail("A collection may contain at most 500 maps in this toolkit.")
    maps = []
    for offset in range(0, len(ids), 100):
        batch = ids[offset:offset + 100]
        fields = {"itemcount": len(batch)}
        fields.update({f"publishedfileids[{index}]": value for index, value in enumerate(batch)})
        found = post_api("GetPublishedFileDetails", fields).get("publishedfiledetails", [])
        by_id = {str(item.get("publishedfileid")): item for item in found}
        for item_id in batch:
            item = by_id.get(item_id, {})
            entry = map_entry(item)
            if entry and entry["id"] == item_id:
                maps.append(entry)
    return maps


def load_state():
    if not STATE.exists():
        return {"collection_id": "", "maps": [], "manual_maps": [], "profiles": {}}
    with STATE.open(encoding="utf-8") as source:
        state = json.load(source)
    if not isinstance(state, dict) or not isinstance(state.get("maps"), list):
        fail("Workshop state is invalid.")
    state.setdefault("profiles", {})
    state.setdefault("manual_maps", [])
    return state


def save_state(state):
    STATE.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(STATE.parent, 0o700)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=STATE.parent,
                                     prefix=".workshop-", delete=False) as output:
        temp = Path(output.name)
        json.dump(state, output, ensure_ascii=False, indent=2)
        output.write("\n")
    try:
        os.chmod(temp, 0o600)
        os.replace(temp, STATE)
    finally:
        temp.unlink(missing_ok=True)


def find_map(state, item_id):
    for item in all_maps(state):
        if item["id"] == item_id:
            return item
    fail(f"Map {item_id} is not in the saved Workshop maps. Add its link or refresh the collection first.")


def all_maps(state):
    return list({item["id"]: item for item in state["maps"] + state["manual_maps"]}.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("collection")
    sub.add_parser("refresh")
    sub.add_parser("clear-collection")
    sub.add_parser("list")
    setting = sub.add_parser("set-collection")
    setting.add_argument("link")
    add = sub.add_parser("add-map")
    add.add_argument("link")
    remove = sub.add_parser("remove-map")
    remove.add_argument("id")
    profile = sub.add_parser("set-profile")
    profile.add_argument("id")
    profile.add_argument("profile", choices=PROFILES)
    item = sub.add_parser("get")
    item.add_argument("id")
    args = parser.parse_args()
    state = load_state()
    if args.action == "collection":
        print(state.get("collection_id", ""))
    elif args.action in ("set-collection", "refresh"):
        collection_id = published_id(args.link) if args.action == "set-collection" else state.get("collection_id", "")
        if not collection_id:
            fail("No Workshop collection is configured yet.")
        maps = fetch_collection(collection_id)
        state.update(collection_id=collection_id, maps=maps)
        save_state(state)
        print(f"Collection {collection_id}: {len(maps)} CS2 maps")
    elif args.action == "clear-collection":
        state.update(collection_id="", maps=[])
        save_state(state)
        print("Workshop collection removed; individually added maps remain.")
    elif args.action == "add-map":
        item_id = published_id(args.link)
        entry = fetch_map(item_id)
        state["manual_maps"] = [item for item in state["manual_maps"] if item["id"] != item_id] + [entry]
        save_state(state)
        print(f"Added {entry['title']} ({item_id})")
    elif args.action == "remove-map":
        item_id = published_id(args.id)
        if not any(item["id"] == item_id for item in state["manual_maps"]):
            fail("This map was not added individually.")
        state["manual_maps"] = [item for item in state["manual_maps"] if item["id"] != item_id]
        if not any(item["id"] == item_id for item in state["maps"]):
            state["profiles"].pop(item_id, None)
        save_state(state)
        print(f"Removed individually added map {item_id}")
    elif args.action == "list":
        for entry in all_maps(state):
            print(f"{entry['id']}\t{state['profiles'].get(entry['id'], 'competitive')}\t{entry['title']}")
    elif args.action == "get":
        item_id = published_id(args.id)
        entry = find_map(state, item_id)
        print(f"{item_id}\t{state['profiles'].get(item_id, 'competitive')}\t{entry['title']}")
    elif args.action == "set-profile":
        item_id = published_id(args.id)
        find_map(state, item_id)
        state["profiles"][item_id] = args.profile
        save_state(state)
        print(f"{item_id}: {args.profile}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
        print(f"Workshop: {exc}", file=sys.stderr)
        sys.exit(1)
