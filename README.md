# CS2 Server Toolkit

<img width="525" height="461" alt="image" src="https://github.com/user-attachments/assets/91c7ace9-3a5e-4b32-abe8-4c19c194581c" />


⚡ One-command installer & admin toolkit for Counter-Strike 2 dedicated servers.  
Includes:
- Automatic installation & updates (via `systemd --user` timers)
- Interactive admin menu (maps, game modes, bans, weapons block, chickens, logs, restart)
- User-level `systemd` service (auto-start after reboot with linger)
- Safe update mechanism (avoids restarts while players are in game)

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
   The installer will ask for:
   - Public server IP
   - RCON password
   - Server name (hostname)
   - Optional join password
   - Game Server Login Token (GSLT)

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

- **Check logs**
  ```bash
  journalctl --user -u cs2-ds -f
  ```

---

---

## ⚙️ Custom game mode configs (`*_server.cfg`)

CS2 loads a base game-mode config and then (if present) a **server override** with the suffix `_server.cfg`.  
This lets you keep your persistent settings separate from Valve defaults and from the toolkit menu.

### Load order (per map change / restart)

1. `gamemode_<mode>.cfg` (Valve defaults)  
2. `gamemode_<mode>_server.cfg` (your overrides — takes priority)  
3. Anything you manually `exec` (e.g., via admin menu)  

Where `<mode>` is one of: `casual`, `competitive`, `wingman`, `deathmatch`, …

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
You can keep this inside a mode’s `_server.cfg` or in a separate file you `exec`:
```cfg
// ban AWP + SCOUT
mp_items_prohibited "weapon_awp,weapon_ssg08"
```

**5) Fun: chickens**
```cfg
mp_enablechickens 1
```

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
- Use the admin menu for **temporary** toggles (e.g., weapon block, quick practice, chickens).  
- If a setting is fighty (e.g., a menu preset also sets it), the last executed file wins.  
- You can create **per-map** overrides using `mapname.cfg` (e.g., `de_mirage.cfg`) if needed.

---

## 🔄 Auto Update

Two timers are installed automatically:

- `cs2-update.timer` → daily update at 06:00  
- `cs2-checkupdate.timer` → safe check every 30 min (updates only if empty)

Check timers:
```bash
systemctl --user list-timers --all | grep cs2
```

---

## 💸 Support / Donate

If you like this project, consider supporting development ❤️

- **USDT (TRC20):** `TGhctG46AciRXEudjEereW8DGvoErdkqta`  
- **USDT (BSC):** `0xCBC1861Ed594a9e39a6995e70067931A955831b6`  
- **USDT (TON):** `UQD4ctGxd4JwueIt8n3n4Ob3p1nyAMrdmkr_tYFFZqQqdNYR`

---

## 📜 License

MIT License © 2025 [Behzad Kiyani](https://github.com/kiyanibehzad)
