#!/usr/bin/env python3
"""Maintain the toolkit's CounterStrikeSharp admins and Metamod loader line."""

import json
import os
import re
import sys
import tempfile
from pathlib import Path


PERMISSION = "@cs2toolkit/admin"
STEAM_ID = re.compile(r"7656119[0-9]{10}\Z")
LOADER = "Game csgo/addons/metamod"


def atomic_write(path: Path, contents: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(contents)
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def read_admins(path: Path) -> dict:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("admins.json must be a JSON object")
    return data


def write_admins(path: Path, data: dict) -> None:
    atomic_write(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def admin_add(path: Path, steam_id: str, label: str) -> None:
    if not STEAM_ID.fullmatch(steam_id):
        raise ValueError("SteamID64 must contain 17 digits and start with 7656119")
    if not label or len(label) > 48:
        raise ValueError("Admin name must contain 1 to 48 characters")
    data = read_admins(path)
    for entry in data.values():
        if isinstance(entry, dict) and entry.get("identity") == steam_id:
            flags = entry.setdefault("flags", [])
            if not isinstance(flags, list):
                raise ValueError("Existing admin flags must be an array")
            if PERMISSION not in flags:
                flags.append(PERMISSION)
            write_admins(path, data)
            return
    if label in data:
        raise ValueError("Admin name already belongs to a different SteamID")
    data[label] = {"identity": steam_id, "flags": [PERMISSION]}
    write_admins(path, data)


def admin_remove(path: Path, steam_id: str) -> None:
    if not STEAM_ID.fullmatch(steam_id):
        raise ValueError("Invalid SteamID64")
    data = read_admins(path)
    for label, entry in list(data.items()):
        if not isinstance(entry, dict) or entry.get("identity") != steam_id:
            continue
        flags = entry.get("flags", [])
        if not isinstance(flags, list):
            raise ValueError("Existing admin flags must be an array")
        entry["flags"] = [flag for flag in flags if flag != PERMISSION]
        if not entry["flags"] and not entry.get("groups"):
            del data[label]
    write_admins(path, data)


def admin_list(path: Path) -> None:
    for label, entry in read_admins(path).items():
        if isinstance(entry, dict) and PERMISSION in entry.get("flags", []):
            print(f"{entry.get('identity', '?')}  {label}")


def repair_loader(path: Path) -> None:
    original = path.read_text(encoding="utf-8")
    lines = original.splitlines(keepends=True)
    search = next((i for i, line in enumerate(lines) if re.match(r"^\s*SearchPaths\s*(//.*)?$", line)), None)
    if search is None:
        raise ValueError("SearchPaths section missing from gameinfo.gi")
    opening = next((i for i in range(search + 1, len(lines)) if lines[i].strip() == "{"), None)
    if opening is None:
        raise ValueError("SearchPaths opening brace missing from gameinfo.gi")
    closing = next((i for i in range(opening + 1, len(lines)) if lines[i].strip() == "}"), None)
    if closing is None:
        raise ValueError("SearchPaths closing brace missing from gameinfo.gi")
    loader_lines = [i for i in range(opening + 1, closing) if re.match(r"^\s*Game\s+csgo/addons/metamod\s*(//.*)?$", lines[i])]
    if loader_lines == [opening + 1]:
        return
    indent = re.match(r"^\s*", lines[opening + 1]).group(0) if opening + 1 < closing else "\t\t"
    for i in reversed(loader_lines):
        del lines[i]
    lines.insert(opening + 1, f"{indent}{LOADER}\n")
    mode = path.stat().st_mode & 0o777
    atomic_write(path, "".join(lines), mode)


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: cs2-ingame-config.py COMMAND PATH [SteamID64] [name]", file=sys.stderr)
        return 2
    command, path = sys.argv[1], Path(sys.argv[2])
    try:
        if command == "admin-add" and len(sys.argv) in (4, 5):
            admin_add(path, sys.argv[3], sys.argv[4] if len(sys.argv) == 5 else f"Toolkit-{sys.argv[3]}")
        elif command == "admin-remove" and len(sys.argv) == 4:
            admin_remove(path, sys.argv[3])
        elif command == "admin-list" and len(sys.argv) == 3:
            admin_list(path)
        elif command == "repair-loader" and len(sys.argv) == 3:
            repair_loader(path)
        else:
            print("Invalid command or arguments", file=sys.stderr)
            return 2
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"[ingame-menu] {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
