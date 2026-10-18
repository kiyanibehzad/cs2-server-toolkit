# CS2 Server Toolkit

![Untitled-1](https://github.com/user-attachments/assets/92064f95-45fa-4700-982d-e96a972f3f2a)


⚡ One-command installer and admin toolkit for Counter-Strike 2 dedicated servers.
Includes:
- Automatic installation, player-safe game and OS updates, and conditional host reboot
- Interactive admin menu with official and Workshop map presets, plus one-key return to Competitive on Dust II
- Persistent bot controls and warmup duration, live voice controls, and weapon restrictions
- Bans, join password, fun settings, logs, restart, and health check
- User-level `systemd` service (auto-start after reboot with linger)
- One safe update path for timers and manual updates
- Source RCON client that reads split responses and keeps the RCON password out of its command line

---

## ☁️ Hosting Recommendation

Looking for a reliable VPS or dedicated server for CS2?  
👉 [Order from iShosting with my referral link](https://ishosting.com/affiliate/NDk5OSM2)

---

## 🖥 Requirements

- **OS**: Ubuntu 24.04 (fresh VPS or dedicated server recommended)  
- **RAM**: 4 GB minimum (8 GB+ recommended)  
- **Disk**: ~60 GB free  
- **User**: Non-root user (e.g. `cs2server`)  

---

## 🚀 Quick Start

1. **Create user**
   ```bash
   sudo adduser cs2server
   sudo usermod -aG sudo cs2server
   su - cs2server
   ```

2. **Clone repository**
   ```bash
   git clone https://github.com/kiyanibehzad/cs2-server-toolkit.git
   cd cs2-server-toolkit
   ```

3. **Run installer**
   ```bash
   chmod +x install.sh
   ./install.sh
   ```
   The installer will ask for these values on the first run:
   - Public server IP (Your server or virtual machine IP)
   - RCON password (Mandatory)
   - Server name (Seen on Steam/Game)
   - Optional join password (It is recommended)
   - [Game Server Login Token (GSLT)](https://steamcommunity.com/dev/managegameservers)

   Run the installer as the game user, not root. Running it again refreshes the
   toolkit files and systemd units while keeping existing game data and settings.
   To update the game itself, use the updater below.
   If an older `~/update-cs2.sh` exists, the installer saves it with a
   `.legacy-<timestamp>` suffix before replacing it with the safe entry point.

---

## 🎮 Usage

- **Start/stop server**  
  ```bash
  systemctl --user start cs2-ds
  systemctl --user stop cs2-ds
  ```

- **Run admin menu**
  ```bash
  ~/admin-cs2
  ```

  Press `A` to choose an Arms Race map: Pool Day, Shoots, Baggage, or Shoots Night.
  This applies the Arms Race preset and changes the map in one action. The menu
  marks maps that are not installed; choosing one leaves the current mode alone.
  Changing a live map interrupts the current match.

  For scripts, use `~/cs2-ds/cs2-admin.sh armsrace-map ar_pool_day` (or
  `ar_shoots` / `ar_baggage` / `ar_shoots_night`).

  Press `R` for Rush. This chooses `rush_001` and applies the Rush preset in
  one action. Valve's Rush uses one map file with arenas selected within the
  match. The option is available when the map is installed. From a shell, use
  `~/cs2-ds/cs2-admin.sh rush-map rush_001`. Switching back to Competitive on
  Dust II is one keypress: `H` in Map Hotkeys. From a shell, use
  `~/cs2-ds/cs2-admin.sh default`.

  Press `P1` through `P6` to choose a preset, then enter its map key. For
  example, `P1` then `1` selects Competitive + Dust II. Enter `1+2` (or `1,2`)
  to switch to two maps in order; the last selected map remains active. The
  whole list is checked before any switch. `P6` shows the Arms Race maps;
  `P7` selects Rush + rush_001 directly. `P0` opens the preset list. From a
  shell, use `~/cs2-ds/cs2-admin.sh preset-maps 1 1+2`.

  Each preset shows only maps supported by its mode. `P3` uses Valve's Wingman
  pool (Debris, El Dorado, Poseidon, Overpass, Vertigo, Nuke, Inferno); Dust II
  is unavailable there. `P5` uses Valve's Retakes pool (Dust II, Mirage,
  Inferno, Nuke, Overpass, Vertigo, Ancient, Train). Competitive, Casual and
  Deathmatch keep the ten full-size defuse maps; Arms Race and Rush have their
  own pools. A map missing from the server is marked and cannot be selected.
  The direct map hotkeys also reject maps outside the active preset.

  Press `K` for Workshop maps. Paste an individual Workshop map link under
  `K` → `a`; the map then appears in the menu. For example, use the link to
  [awp_india](https://steamcommunity.com/sharedfiles/filedetails/?id=3070290869).
  Use `K` → `d` to remove an individually added map. Steam's public API does
  not expose your personal subscribed-item list to a community server, so
  subscribing on your PC alone cannot populate this menu. To keep a larger
  list together, put those maps in a [Steam Workshop Collection](https://steamcommunity.com/workshop/browse/?appid=730&section=collections)
  and enter its link once under `K` → `c`. Opening `K` refreshes that list;
  `r` refreshes it again, and `x` clears the collection without removing maps
  added individually. If Steam is unavailable, the last saved list remains
  visible. Only CS2 items tagged as maps are shown, so weapon finishes are
  skipped. Collections must be visible to Steam's public API. Selecting a map
  asks CS2 to download its current Workshop version and switch to it. The
  first download can take time and changing maps interrupts a live match.

  Each Workshop map starts with the Competitive preset. Under `K` → `p`, save
  `AWP only` or `Scout only` for that map. Selecting its number then applies
  the saved preset with the map. These sniper presets give both teams the
  chosen rifle on spawn, remove the default pistol and buying, and give
  armor. `H` returns to the standard Competitive + Dust II equipment.
  The collection and saved presets live in `~/cs2-ds/toolkit-config/workshop.json`
  and survive toolkit updates. For scripts, use `workshop-set-collection URL`,
  `workshop-refresh`, `workshop-add-map URL`, `workshop-list`,
  `workshop-set-profile ID awp|scout|competitive`,
  and `workshop-play ID [preset]` with `~/cs2-ds/cs2-admin.sh`.

  The Bot Management submenu (`b0`) shows the live bot count, target,
  quota mode, and difficulty. You can turn bots on, turn them off and kick
  them, add several at once, set an exact target, or choose difficulty
  (0 easy, 1 normal, 2 hard, 3 expert). Changing difficulty updates the saved
  setting and newly added bots without kicking every bot at once. The menu
  refuses a target above the available player slots. The target is a bot count
  in `normal` quota mode. The chosen count and difficulty persist across map
  changes and restarts. Turning bots on after turning them off restores the
  last count.

  For quick use, press two keys without Enter: `b1` turns bots on, `b2` turns
  them off and kicks them, `b3` adds several, `b4` sets an exact count, and
  `b5` changes difficulty. `b0` opens the detailed bot menu.

  The Live Voice submenu (`v0`) offers teammates together with open voice during
  warmup/halftime/end, living teammates with dead players across both teams,
  both playing teams together, the current mode's original voice settings,
  strict team voice, or everyone including spectators. Changes apply
  immediately through RCON; no restart is needed. The first voice change on
  each map/server process saves its previous settings for the Restore option.
  From a shell, use `~/cs2-ds/cs2-admin.sh voice-mode both-teams`,
  `voice-mode default`, or `voice-status`.
  In the main menu, `v1` through `v6` select those choices directly without
  Enter; `v0` opens the detailed voice menu.
  CS2's dead-player controls affect text chat as well as voice. Voice choices
  are temporary and game mode or server restarts may reset them.

  Press `W` for Warmup. The initial server-wide choice is 30 seconds, including
  Home. Save an on/off choice and a duration from 1 to 3600 seconds; the saved
  choice then applies on future maps and restarts. Turning warmup off
  also ends the current warmup. From a shell, use
  `~/cs2-ds/cs2-admin.sh warmup-set 45` or `warmup-set 0`.

  The admin menu shows its own version in the title, separate from the CS2
  game version. Warmup has its own section on the main screen.

  Press `m` for the less frequent maintenance tools: game update, service
  restart, logs, backup, RCON, game and OS timer status, Git menu update, and
  health check. The old `Kick ALL` action was removed because `kickall` is not
  a CS2 server command. Use `b2` to remove bots.

  Run `~/cs2-ds/cs2-admin.sh health` for a read-only service, RCON, port,
  build and file-permission check. Steam/VAC login is reported as unknown when
  the game does not expose a reliable status signal.

- **Check logs**
  ```bash
  journalctl --user -u cs2-ds -f
  ```

---

## ⚙️ Configuration and game modes

`.update.env` holds the toolkit's private launch settings, including GSLT,
network settings and RCON credentials. `start.sh` reads it on every start.
GSLT is passed to the game at launch; `cs2server.cfg` is no longer a second
toolkit source for it. Existing duplicate GSLT lines are removed during
reinstallation after a restricted backup is made.

The weapon menu saves the chosen list in `~/cs2-ds/toolkit-config/blocked-weapons.txt`.
The bot menu saves its explicit choices in `~/cs2-ds/toolkit-config/bots.txt`.
The initial 30-second warmup and later menu choices are saved in
`~/cs2-ds/toolkit-config/warmup.txt`.
The toolkit generates `game/csgo/cfg/cs2_toolkit.cfg` and includes it from
`cs2server.cfg` and the supported `gamemode_*_server.cfg` override files.
These includes are recreated at server start. Valve's `gamemode_*.cfg` base
files are never edited by the toolkit. Until you use the bot menu, each mode's
existing bot defaults still apply. The menu's Fun and Voice settings are temporary;
the join password is persistent in `.update.env` and `cs2server.cfg`.

Mode switches set `game_type`, `game_mode`, `sv_game_mode_flags` and
`sv_skirmish_id` before the map loads, then read back the resulting values.
The Competitive preset also reapplies and checks MR12 overtime settings.

### Your own mode overrides (`*_server.cfg`)

CS2 loads a base game-mode config and then (if present) a **server override** with the suffix `_server.cfg`.  
This lets you keep your persistent settings separate from Valve defaults and from the toolkit menu.

### Load order (per map change / restart)

1. `gamemode_<mode>.cfg` (Valve defaults)  
2. `gamemode_<mode>_server.cfg` (your overrides — takes priority)  
3. Anything you manually `exec` (e.g., via admin menu)  

For example, Competitive uses `gamemode_competitive_server.cfg`, Wingman uses
`gamemode_competitive2v2_server.cfg`, Retakes uses
`gamemode_retakecasual_server.cfg`, and Arms Race uses
`gamemode_armsrace_server.cfg`. Rush uses `gamemode_rush_server.cfg`. The file
stem does not always match the menu
name.

### File locations

Put your files here (created if missing):
```
/home/<user>/cs2-ds/game/csgo/cfg/gamemode_competitive_server.cfg
/home/<user>/cs2-ds/game/csgo/cfg/gamemode_casual_server.cfg
/home/<user>/cs2-ds/game/csgo/cfg/gamemode_deathmatch_server.cfg
...
```

> If your build uses `game/cs2/cfg/`, use that path instead. The toolkit auto-detects.

### Quick examples

**1) Competitive MR12 (overtime 3+3, keep >10 players)**  
`gamemode_competitive_server.cfg`
```cfg
mp_maxrounds 24
mp_halftime 1
mp_overtime_enable 1
mp_overtime_maxrounds 6
mp_freezetime 15
mp_roundtime 1.92
mp_round_restart_delay 7
mp_autokick 0
sv_visiblemaxplayers 32
```

**2) Casual tweaks**  
`gamemode_casual_server.cfg`
```cfg
mp_maxrounds 15
mp_free_armor 1
mp_solid_teammates 0
sv_visiblemaxplayers 32
```

**3) Deathmatch (FFA-style)**  
`gamemode_deathmatch_server.cfg`
```cfg
mp_teammates_are_enemies 1
mp_respawn_on_death_t 1
mp_respawn_on_death_ct 1
mp_randomspawn 1
mp_freezetime 0
mp_maxrounds 0
mp_timelimit 20
mp_ignore_round_win_conditions 1
sv_visiblemaxplayers 32
```

**4) Weapon restrictions (global)**  
Use the `w` menu or `weapons-set` command. Friendly names and supported
canonical names are converted to item definition indices, which is what
`mp_items_prohibited` expects. For example:
```cfg
// AWP (9) and SSG 08 (40)
mp_items_prohibited "9,40"
```
Manual lines in other configs may override the toolkit value; the menu's saved
list is applied at the end of each supported mode override and mode switch.
Check an actual buy attempt in CS2 after changing restrictions, since a ConVar
readback alone does not prove game-rule enforcement.

**5) Fun: chickens**
Use the Fun menu to spawn chickens with `ent_create chicken`. The obsolete
`mp_enablechickens` command is not supported by the current server.

### Applying changes

- Changes in `*_server.cfg` load automatically on next **map change** or server restart.  
- To apply immediately:
  ```
  rcon exec gamemode_competitive_server.cfg
  rcon mp_restartgame 1
  ```
  (replace filename with your target mode)

### Tips & best practices

- Keep permanent, “always-on” rules in the relevant `*_server.cfg`.  
- Use the admin menu for temporary Fun commands and the persistent weapon list.
- If a setting is fighty (e.g., a menu preset also sets it), the last executed file wins.  
- You can create **per-map** overrides using `mapname.cfg` (e.g., `de_mirage.cfg`) if needed.

---

## 🔄 Updates

Game updates and morning maintenance use separate timers with a shared lock:

- `cs2-update.timer` → daily check at 06:00
- `cs2-checkupdate.timer` → check every 30 minutes
- `cs2-daily-home.timer` → from 06:00 to noon, try every five minutes until the
  first empty moment; restart once and apply Competitive MR12 on Dust II
- `cs2-os-maintenance@<game-user>.timer` → from 06:10 to noon, try every ten
  minutes; update Ubuntu packages and reboot only if required and no real
  players are online

The schedule uses the server's local time. If RCON cannot confirm the number
of real players, maintenance waits. A daily Home restart is skipped if the
server stays occupied through the morning. The installer replaces Ubuntu's
floating `apt-daily.timer` and `apt-daily-upgrade.timer` with the root-owned,
player-safe OS timer. It preserves package configuration and does not remove
packages during upgrades. OS update and reboot logs are in
`journalctl -u cs2-os-maintenance@<game-user>.service`.

When a new build is available, the updater checks the player count through
RCON. If players are present or RCON cannot be trusted, it defers the update.
It also prevents overlapping runs and restarts a previously running server if
SteamCMD fails. A stopped server remains stopped. After SteamCMD reports
success, the updater checks the installed manifest, executable and known
public build before reporting a verified update.

Run a check or request an update manually:

```bash
~/cs2-ds/cs2-safe-update.sh --check
~/cs2-ds/cs2-safe-update.sh --force
# Existing servers can also use the familiar command:
~/update-cs2.sh
```

`--force` skips only the build comparison. It still defers while players are
connected or RCON status is unavailable.

Check timers:
```bash
systemctl --user list-timers --all | grep cs2
```

Update and server logs:

```bash
tail -f ~/cs2-ds/update.log
journalctl --user -u cs2-checkupdate.service -n 50 --no-pager
journalctl --user -u cs2-ds.service -n 50 --no-pager
```

The installer restricts `.update.env` and `cs2server.cfg` to the game user.
Do not commit these files or paste their contents into an issue: they hold
RCON credentials and possibly the GSLT.

References: [Valve's CS2 server launch example](https://github.com/ValveSoftware/counter-strike_rules_and_regs/blob/main/major-supplemental-rulebook.md),
[Valve Developer Community game modes](https://developer.valvesoftware.com/wiki/Counter-Strike:_Global_Offensive/Game_Modes),
[SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD), and
[Source RCON protocol](https://developer.valvesoftware.com/wiki/Source_RCON_Protocol).

---

## 💸 Support / Donate

If you like this project, consider supporting development ❤️

- **USDT (TRC20):** `TGhctG46AciRXEudjEereW8DGvoErdkqta`  
- **USDT (BSC):** `0xCBC1861Ed594a9e39a6995e70067931A955831b6`  
- **USDT (TON):** `UQD4ctGxd4JwueIt8n3n4Ob3p1nyAMrdmkr_tYFFZqQqdNYR`

---

## 📜 License

MIT License © 2025 [Behzad Kiyani](https://github.com/kiyanibehzad)
