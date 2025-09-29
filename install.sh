#!/bin/bash
set -euo pipefail

# ---------- Defaults ----------
CS2_USER="${CS2_USER:-cs2server}"
CS2_HOME="/home/$CS2_USER"
CS2_DIR="$CS2_HOME/cs2-ds"
HOST_IP="${HOST_IP:-}"
PORT="${PORT:-27015}"
RCON_PASS="${RCON_PASS:-}"
SERVER_NAME="${SERVER_NAME:-CS2 Server}"
WITH_TIMER="${WITH_TIMER:-1}"
WITH_SAFE_CHECK="${WITH_SAFE_CHECK:-1}"

# ---------- Helper ----------
ask_if_empty() {
  local varname="$1" prompt="$2" def="${3:-}"
  eval "val=\${$varname:-}"
  if [ -z "$val" ]; then
    if [ -n "$def" ]; then
      read -rp "$prompt [$def]: " val
      val="${val:-$def}"
    else
      read -rp "$prompt: " val
    fi
    eval "$varname=\$val"
  fi
}

# ---------- Interactive prompts ----------
ask_if_empty CS2_USER    "Enter Linux username for server" "cs2server"
CS2_HOME="/home/$CS2_USER"
CS2_DIR="$CS2_HOME/cs2-ds"

ask_if_empty HOST_IP     "Enter public server IP"
ask_if_empty PORT        "Enter server port" "27015"
ask_if_empty RCON_PASS   "Enter RCON password"
ask_if_empty SERVER_NAME "Enter visible server hostname" "CS2 Server"

echo
echo "== Summary =="
echo " Linux user : $CS2_USER"
echo " Public IP  : $HOST_IP"
echo " Port       : $PORT"
echo " RCON pass  : $RCON_PASS"
echo " Server name: $SERVER_NAME"
echo

# ---------- Install deps ----------
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates lib32gcc-s1 git build-essential
fi

# ---------- SteamCMD ----------
if [[ ! -x "$CS2_HOME/steamcmd/steamcmd.sh" ]]; then
  mkdir -p "$CS2_HOME/steamcmd"
  (cd "$CS2_HOME/steamcmd" && curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz)
fi

# ---------- mcrcon ----------
if ! command -v mcrcon >/dev/null 2>&1; then
  TMP="$(mktemp -d)"
  git clone --depth 1 https://github.com/Tiiffi/mcrcon.git "$TMP/mcrcon"
  make -C "$TMP/mcrcon"
  sudo install -m 0755 "$TMP/mcrcon/mcrcon" /usr/local/bin/mcrcon
  rm -rf "$TMP"
fi

mkdir -p "$CS2_DIR" "$CS2_HOME/.config/systemd/user" "$CS2_DIR/backups"

# ---------- Fetch/update CS2 ----------
"$CS2_HOME/steamcmd/steamcmd.sh" +login anonymous +force_install_dir "$CS2_DIR" +app_update 730 validate +quit

# ---------- Copy scripts ----------
install -m 0755 scripts/cs2-admin.sh "$CS2_DIR/cs2-admin.sh"
install -m 0755 scripts/cs2-safe-update.sh "$CS2_DIR/cs2-safe-update.sh"
install -m 0755 scripts/start.sh "$CS2_DIR/start.sh"

# ---------- Patch placeholders ----------
sed -i "s|CS2USER|$CS2_USER|g" "$CS2_DIR/start.sh" "$CS2_DIR/cs2-safe-update.sh" systemd/cs2-ds.env
sed -i "s|^IP=.*|IP=\"$HOST_IP\"|" "$CS2_DIR/start.sh"
sed -i "s|^PORT=.*|PORT=\"$PORT\"|" "$CS2_DIR/start.sh"

# ---------- .update.env ----------
cat > "$CS2_DIR/.update.env" <<EOV
HOST_IP="$HOST_IP"
PORT="$PORT"
RCON_PASS="$RCON_PASS"
SERVER_NAME="$SERVER_NAME"
EOV

# ---------- server.cfg ----------
CFG="$CS2_DIR/game/csgo/cfg/cs2server.cfg"
mkdir -p "$(dirname "$CFG")"
cat > "$CFG" <<EOF
hostname "$SERVER_NAME"
rcon_password "$RCON_PASS"
sv_password ""
sv_lan 0
bot_quota 0
mp_maxrounds 24
mp_halftime 1
mp_overtime_enable 1
mp_overtime_maxrounds 6
mp_freezetime 15
mp_buytime 20
mp_autokick 0
EOF

# ---------- Systemd units ----------
install -m 0644 systemd/cs2-ds.env "$CS2_HOME/.config/systemd/user/cs2-ds.env"
install -m 0644 systemd/cs2-ds.service "$CS2_HOME/.config/systemd/user/cs2-ds.service"

# Optional timers
if [[ "$WITH_TIMER" -eq 1 ]]; then
  install -m 0644 systemd/cs2-update.service "$CS2_HOME/.config/systemd/user/cs2-update.service"
  install -m 0644 systemd/cs2-update.timer "$CS2_HOME/.config/systemd/user/cs2-update.timer"
  sed -i "s|/home/CS2USER|/home/$CS2_USER|g" "$CS2_HOME/.config/systemd/user/cs2-update.service"
fi
if [[ "$WITH_SAFE_CHECK" -eq 1 ]]; then
  install -m 0644 systemd/cs2-checkupdate.service "$CS2_HOME/.config/systemd/user/cs2-checkupdate.service"
  install -m 0644 systemd/cs2-checkupdate.timer "$CS2_HOME/.config/systemd/user/cs2-checkupdate.timer"
  sed -i "s|/home/CS2USER|/home/$CS2_USER|g" "$CS2_HOME/.config/systemd/user/cs2-checkupdate.service"
fi

# ---------- Enable services ----------
loginctl enable-linger "$CS2_USER" 2>/dev/null || sudo loginctl enable-linger "$CS2_USER" || true
systemctl --user daemon-reload
systemctl --user enable --now cs2-ds
[[ "$WITH_TIMER" -eq 1 ]] && systemctl --user enable --now cs2-update.timer || true
[[ "$WITH_SAFE_CHECK" -eq 1 ]] && systemctl --user enable --now cs2-checkupdate.timer || true

# Symlink admin menu
ln -sf "$CS2_DIR/cs2-admin.sh" "$CS2_HOME/admin-cs2"

echo
echo "Install complete!"
echo " Server user : $CS2_USER"
echo " Host IP     : $HOST_IP"
echo " Port        : $PORT"
echo " RCON pass   : $RCON_PASS"
echo " Server name : $SERVER_NAME"
echo
echo "Run admin menu with: ~/admin-cs2"
EOF
chmod +x install.sh
