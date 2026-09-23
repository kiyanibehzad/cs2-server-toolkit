#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CS2_USER="$(id -un)"
CS2_HOME="$HOME"
CS2_DIR="$CS2_HOME/cs2-ds"
UNIT_DIR="$CS2_HOME/.config/systemd/user"
CONF="$CS2_DIR/.update.env"
WITH_TIMER="${WITH_TIMER:-1}"
WITH_SAFE_CHECK="${WITH_SAFE_CHECK:-1}"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run this installer as the dedicated, non-root game user." >&2
  exit 1
fi
if [[ "$CS2_HOME" != "$(getent passwd "$CS2_USER" | cut -d: -f6)" ]]; then
  echo "HOME does not match the current user's home directory." >&2
  exit 1
fi

ask_required() {
  local name="$1" prompt="$2" value="${!1:-}"
  while [[ -z "$value" ]]; do
    if [[ "$name" == RCON_PASS && -t 0 ]]; then
      read -r -s -p "$prompt: " value; echo
    else
      read -r -p "$prompt: " value
    fi
  done
  printf -v "$name" '%s' "$value"
}

# Console commands and cfg files cannot safely contain command separators or
# control characters in these fields.
check_cfg_value() {
  local name="$1" value="$2"
  if [[ "$value" == *[\;\"\\]* || "$value" =~ [[:cntrl:]] ]]; then
    echo "Invalid character in $name (semicolon, quote, backslash, or control character)." >&2
    exit 1
  fi
}

if [[ -f "$CONF" ]]; then
  # Reinstalling the toolkit must not replace the server's credentials.
  # shellcheck disable=SC1090
  . "$CONF"
  echo "Using existing settings from $CONF"
else
  HOST_IP="${HOST_IP:-}"
  PORT="${PORT:-27015}"
  RCON_PASS="${RCON_PASS:-}"
  SERVER_NAME="${SERVER_NAME:-CS2 Server}"
  SERVER_PASS="${SERVER_PASS:-}"
  GSLT="${GSLT:-}"

  ask_required HOST_IP "Public server IP"
  ask_required RCON_PASS "RCON password"
  if [[ -t 0 ]]; then
    read -r -p "Server port [$PORT]: " input
    PORT="${input:-$PORT}"
    read -r -p "Server name [$SERVER_NAME]: " input
    SERVER_NAME="${input:-$SERVER_NAME}"
    read -r -s -p "Join password (blank for none): " input; echo
    SERVER_PASS="${input:-$SERVER_PASS}"
    read -r -s -p "GSLT (blank for none): " input; echo
    GSLT="${input:-$GSLT}"
  fi
fi

HOST_IP="${HOST_IP:-}"
PORT="${PORT:-27015}"
RCON_PASS="${RCON_PASS:-}"
SERVER_NAME="${SERVER_NAME:-CS2 Server}"
SERVER_PASS="${SERVER_PASS:-}"
GSLT="${GSLT:-}"
[[ -n "$HOST_IP" && -n "$RCON_PASS" ]] || { echo "IP and RCON password are required." >&2; exit 1; }
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || {
  echo "PORT must be between 1 and 65535." >&2; exit 1;
}
for field in HOST_IP RCON_PASS SERVER_NAME SERVER_PASS GSLT; do
  check_cfg_value "$field" "${!field}"
done

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates lib32gcc-s1 git util-linux python3
fi

if [[ ! -x "$CS2_HOME/steamcmd/steamcmd.sh" ]]; then
  mkdir -p "$CS2_HOME/steamcmd"
  (cd "$CS2_HOME/steamcmd" && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz)
fi

mkdir -p "$CS2_DIR" "$UNIT_DIR" "$CS2_DIR/backups"
chmod 700 "$CS2_DIR/backups"
if [[ ! -x "$CS2_DIR/game/bin/linuxsteamrt64/cs2" ]]; then
  "$CS2_HOME/steamcmd/steamcmd.sh" +force_install_dir "$CS2_DIR" +login anonymous +app_update 730 validate +quit
else
  echo "Game already installed; use cs2-safe-update.sh for game updates."
fi

install -m 0755 "$REPO_DIR/scripts/cs2-admin.sh" "$CS2_DIR/cs2-admin.sh"
install -m 0755 "$REPO_DIR/scripts/cs2-config.sh" "$CS2_DIR/cs2-config.sh"
install -m 0755 "$REPO_DIR/scripts/cs2-rcon.py" "$CS2_DIR/cs2-rcon.py"
install -m 0755 "$REPO_DIR/scripts/cs2-buildid.py" "$CS2_DIR/cs2-buildid.py"
install -m 0755 "$REPO_DIR/scripts/cs2-health.sh" "$CS2_DIR/cs2-health.sh"
install -m 0755 "$REPO_DIR/scripts/cs2-safe-update.sh" "$CS2_DIR/cs2-safe-update.sh"
install -m 0755 "$REPO_DIR/scripts/update-cs2.sh" "$CS2_DIR/update-cs2.sh"
install -m 0755 "$REPO_DIR/scripts/start.sh" "$CS2_DIR/start.sh"
if [[ -e "$CS2_HOME/update-cs2.sh" || -L "$CS2_HOME/update-cs2.sh" ]]; then
  if [[ "$(readlink "$CS2_HOME/update-cs2.sh" 2>/dev/null || true)" != "$CS2_DIR/update-cs2.sh" ]]; then
    legacy="$CS2_HOME/update-cs2.sh.legacy-$(date +%Y%m%d%H%M%S)"
    while [[ -e "$legacy" || -L "$legacy" ]]; do legacy="$legacy.$RANDOM"; done
    mv "$CS2_HOME/update-cs2.sh" "$legacy"
    echo "Previous manual updater saved at $legacy"
  fi
fi
ln -sfn "$CS2_DIR/update-cs2.sh" "$CS2_HOME/update-cs2.sh"

if [[ ! -f "$CONF" ]]; then
  umask 077
  {
    for field in HOST_IP PORT RCON_PASS SERVER_NAME SERVER_PASS GSLT; do
      printf '%s=%q\n' "$field" "${!field}"
    done
  } > "$CONF"
fi
chmod 600 "$CONF"

CFG="$CS2_DIR/game/csgo/cfg/cs2server.cfg"
mkdir -p "$(dirname "$CFG")"
if [[ ! -f "$CFG" ]]; then
  umask 077
  {
    printf 'hostname "%s"\n' "$SERVER_NAME"
    printf 'rcon_password "%s"\n' "$RCON_PASS"
    printf 'sv_password "%s"\n' "$SERVER_PASS"
    printf '%s\n' 'sv_lan 0' 'bot_quota 0' 'mp_maxrounds 24' 'mp_halftime 1' \
      'mp_overtime_enable 1' 'mp_overtime_maxrounds 6' 'mp_freezetime 15' \
      'mp_buytime 20' 'mp_autokick 0'
  } > "$CFG"
fi
chmod 600 "$CFG"
if [[ -n "$GSLT" ]] && grep -Eq '^[[:space:]]*sv_setsteamaccount[[:space:]]' "$CFG"; then
  cp -p "$CFG" "$CFG.before-gslt-migration"
  sed -i '/^[[:space:]]*sv_setsteamaccount[[:space:]]/d' "$CFG"
  chmod 600 "$CFG"
  echo "Removed duplicate GSLT setting from cs2server.cfg (backup saved)."
fi
"$CS2_DIR/cs2-config.sh" sync

umask 077
cat > "$UNIT_DIR/cs2-ds.env" <<EOF
LD_LIBRARY_PATH="$CS2_DIR/game/bin/linuxsteamrt64:$CS2_DIR/game/csgo/bin/linuxsteamrt64:$CS2_HOME/steamcmd/linux64"
USER="$CS2_USER"
HOME="$CS2_HOME"
LANG=C.UTF-8
LC_ALL=C.UTF-8
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin:/usr/games
SDL_AUDIODRIVER=dummy
DISPLAY=
EOF
chmod 600 "$UNIT_DIR/cs2-ds.env"
install -m 0644 "$REPO_DIR/systemd/cs2-ds.service" "$UNIT_DIR/cs2-ds.service"
install -m 0644 "$REPO_DIR/systemd/cs2-update.service" "$UNIT_DIR/cs2-update.service"
install -m 0644 "$REPO_DIR/systemd/cs2-update.timer" "$UNIT_DIR/cs2-update.timer"
install -m 0644 "$REPO_DIR/systemd/cs2-checkupdate.service" "$UNIT_DIR/cs2-checkupdate.service"
install -m 0644 "$REPO_DIR/systemd/cs2-checkupdate.timer" "$UNIT_DIR/cs2-checkupdate.timer"

sudo loginctl enable-linger "$CS2_USER"
systemctl --user daemon-reload
systemctl --user enable --now cs2-ds.service
if [[ "$WITH_TIMER" == 1 ]]; then
  systemctl --user enable --now cs2-update.timer
else
  systemctl --user disable --now cs2-update.timer
fi
if [[ "$WITH_SAFE_CHECK" == 1 ]]; then
  systemctl --user enable --now cs2-checkupdate.timer
else
  systemctl --user disable --now cs2-checkupdate.timer
fi
ln -sfn "$CS2_DIR/cs2-admin.sh" "$CS2_HOME/admin-cs2"

echo "Installation complete. Server data and existing settings were preserved."
echo "Admin menu: $CS2_HOME/admin-cs2"
