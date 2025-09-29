# CS2 Server Toolkit

<img width="565" height="501" alt="image" src="https://github.com/user-attachments/assets/0c8b99c2-a925-4b59-95ed-519a2ae5d222" />


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
