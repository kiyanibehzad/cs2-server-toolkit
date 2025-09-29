#!/bin/bash
set -euo pipefail

# ---------- Defaults & helpers ----------
DEFAULT_USER="$(id -un 2>/dev/null || whoami || echo cs2server)"

CS2_USER="${CS2_USER:-$DEFAULT_USER}"
CS2_HOME="${CS2_HOME:-/home/$CS2_USER}"
CS2_DIR="${CS2_DIR:-$CS2_HOME/cs2-ds}"
HOST_IP="${HOST_IP:-}"
PORT="${PORT:-27015}"
RCON_PASS="${RCON_PASS:-}"
SERVER_NAME="${SERVER_NAME:-CS2 Server}"
SERVER_PASS="${SERVER_PASS:-}"
GSLT="${GSLT:-}"
WITH_TIMER="${WITH_TIMER:-1}"
WITH_SAFE_CHECK="${WITH_SAFE_CHECK:-1}"

ask_if_empty() {
  local varname="$1" prompt="$2" def="${3:-}"
  local val; eval "val=\${$varname:-}"
  while [ -z "${val}" ]; do
    if [ -n "$def" ]; then
      read -rp "$prompt [$def]: " val
      val="${val:-$def}"
    else
      read -rp "$prompt: " val
    fi
    eval "$varname=\$val"
  done
}

ensure_nonempty() {
  local name="$1" value="$2"
  if [ -z "$value" ]; then
    echo "ERROR: $name is empty. Aborting." >&2
    exit 1
  fi
}

# ---------- Guard rails ----------
if [ "$(id -u)" -eq 0 ]; then
  echo "WARNING: Running as root is not recommended. Please run as the game user (e.g. cs2server)." >&2
fi

# ---------- Interactive prompts ----------
ask_if_empty CS2_USER    "Enter Linux username for server" "$DEFAULT_USER"
CS2_HOME="/home/$CS2_USER"
CS2_DIR="$CS2_HOME/cs2-ds"

ask_if_empty HOST_IP     "Enter public server IP"
ask_if_empty PORT        "Enter server port" "27015"
ask_if_empty RCON_PASS   "Enter RCON password"
ask_if_empty SERVER_NAME "Enter visible server hostname" "CS2 Server"
# join password can be empty, ask once (no loop)
read -rp "Enter join password (sv_password, leave empty for none): " SERVER_PASS || true
# GSLT can be empty, ask once
read -rp "Enter Game Server Login Token (GSLT, leave empty if not using): " GSLT || true

# sanity
ensure_nonempty "CS2_USER" "$CS2_USER"
ensure_nonempty "HOST_IP" "$HOST_IP"
ensure_nonempty "PORT" "$PORT"
ensure_nonempty "RCON_PASS" "$RCON_PASS"
ensure_nonempty "SERVER_NAME" "$SERVER_NAME"

echo
echo "== Summary =="
echo " Linux user : $CS2_USER"
echo " Public IP  : $HOST_IP"
echo " Port       : $PORT"
echo " RCON pass  : (hidden)"
echo " Server name: $SERVER_NAME"
echo " Join pass  : $( [ -n "$SERVER_PASS" ] && echo set || echo none )"
echo " GSLT       : $( [ -n "$GSLT" ] && echo set || echo none )"
echo

# ---------- Deps ----------
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

# ---------- Dirs ----------
mkdir -p "$CS2_DIR" "$CS2_HOME/.config/systemd/user" "$CS2_DIR/backups"

# ---------- Fetch/update CS2 ----------
"$CS2_HOME/steamcmd/steamcmd.sh" +login anonymous +force_install_dir "$CS2_DIR" +app_update 730 validate +quit

# ---------- Copy scripts ----------
install -m 0755 scripts/cs2-admin.sh       "$CS2_DIR/cs2-admin.sh"       || true
install -m 0755 scripts/cs2-safe-update.sh "$CS2_DIR/cs2-safe-update.sh"
install -m 0755 scripts/start.sh           "$CS2_DIR/start.sh"

# ---------- Patch placeholders ----------
sed -i "s|CS2USER|$CS2_USER|g" systemd/cs2-ds.env 2>/dev/null || true
sed -i "s|CS2USER|$CS2_USER|g" "$CS2_DIR/cs2-safe-update.sh"  2>/dev/null || true
sed -i "s|CS2USER|$CS2_USER|g" "$CS2_DIR/start.sh"            2>/dev/null || true
sed -i "s|^IP=.*|IP=\"$HOST_IP\"|"   "$CS2_DIR/start.sh"
sed -i "s|^PORT=.*|PORT=\"$PORT\"|"  "$CS2_DIR/start.sh"

# ---------- .update.env ----------
cat > "$CS2_DIR/.update.env" <<EOV
HOST_IP="$HOST_IP"
PORT="$PORT"
RCON_PASS="$RCON_PASS"
SERVER_NAME="$SERVER_NAME"
SERVER_PASS="$SERVER_PASS"
GSLT="$GSLT"
EOV
chmod 600 "$CS2_DIR/.update.env"

# ---------- server cfg ----------
CFG="$CS2_DIR/game/csgo/cfg/cs2server.cfg"
mkdir -p "$(dirname "$CFG")"
{
  echo "hostname \"$SERVER_NAME\""
  echo "rcon_password \"$RCON_PASS\""
  echo "sv_password \"$SERVER_PASS\""
  echo "sv_lan 0"
  echo "bot_quota 0"
  echo "mp_maxrounds 24"
  echo "mp_halftime 1"
  echo "mp_overtime_enable 1"
  echo "mp_overtime_maxrounds 6"
  echo "mp_freezetime 15"
  echo "mp_buytime 20"
  echo "mp_autokick 0"
  if [ -n "$GSLT" ]; then
    echo "sv_setsteamaccount \"$GSLT\""
  fi
} > "$CFG"

# ---------- Systemd units ----------
install -m 0644 systemd/cs2-ds.env     "$CS2_HOME/.config/systemd/user/cs2-ds.env"
install -m 0644 systemd/cs2-ds.service "$CS2_HOME/.config/systemd/user/cs2-ds.service"

if [[ "$WITH_TIMER" -eq 1 ]]; then
  install -m 0644 systemd/cs2-update.service "$CS2_HOME/.config/systemd/user/cs2-update.service"
  install -m 0644 systemd/cs2-update.timer   "$CS2_HOME/.config/systemd/user/cs2-update.timer"
  sed -i "s|/home/CS2USER|/home/$CS2_USER|g" "$CS2_HOME/.config/systemd/user/cs2-update.service"
fi
if [[ "$WITH_SAFE_CHECK" -eq 1 ]]; then
  install -m 0644 systemd/cs2-checkupdate.service "$CS2_HOME/.config/systemd/user/cs2-checkupdate.service"
  install -m 0644 systemd/cs2-checkupdate.timer   "$CS2_HOME/.config/systemd/user/cs2-checkupdate.timer"
  sed -i "s|/home/CS2USER|/home/$CS2_USER|g"       "$CS2_HOME/.config/systemd/user/cs2-checkupdate.service"
fi

# ---------- Enable services ----------
loginctl enable-linger "$CS2_USER" 2>/dev/null || sudo loginctl enable-linger "$CS2_USER" || true
systemctl --user daemon-reload
systemctl --user enable --now cs2-ds
[[ "$WITH_TIMER" -eq 1 ]]      && systemctl --user enable --now cs2-update.timer      || true
[[ "$WITH_SAFE_CHECK" -eq 1 ]] && systemctl --user enable --now cs2-checkupdate.timer || true

# ---------- Symlink ----------
ln -sf "$CS2_DIR/cs2-admin.sh" "$CS2_HOME/admin-cs2" || true

echo
echo "Install complete!"
echo " Server user : $CS2_USER"
echo " Host IP     : $HOST_IP"
echo " Port        : $PORT"
echo " RCON pass   : (hidden)"
echo " Server name : $SERVER_NAME"
echo " Join pass   : $( [ -n "$SERVER_PASS" ] && echo set || echo none )"
echo " GSLT        : $( [ -n "$GSLT" ] && echo set || echo none )"
echo
echo "Run admin menu with: $CS2_HOME/admin-cs2"
