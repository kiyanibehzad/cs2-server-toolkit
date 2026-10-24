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
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"

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
  BIND_IP="${BIND_IP:-}"
  RCON_HOST="${RCON_HOST:-}"
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
BIND_IP="${BIND_IP:-}"
RCON_HOST="${RCON_HOST:-}"
PORT="${PORT:-27015}"
RCON_PASS="${RCON_PASS:-}"
SERVER_NAME="${SERVER_NAME:-CS2 Server}"
SERVER_PASS="${SERVER_PASS:-}"
GSLT="${GSLT:-}"
[[ -n "$HOST_IP" && -n "$RCON_PASS" ]] || { echo "IP and RCON password are required." >&2; exit 1; }
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || {
  echo "PORT must be between 1 and 65535." >&2; exit 1;
}
for field in HOST_IP BIND_IP RCON_HOST RCON_PASS SERVER_NAME SERVER_PASS GSLT; do
  check_cfg_value "$field" "${!field}"
done

if [[ "$(uname -m)" != x86_64 ]]; then
  echo 'CS2 dedicated server requires an x86_64 host.' >&2
  exit 1
fi
if [[ ! -r "$OS_RELEASE_FILE" ]]; then
  echo "Cannot read OS release information: $OS_RELEASE_FILE" >&2
  exit 1
fi
# /etc/os-release is provided by the OS; use a subshell so its variables do not
# override the installer configuration loaded above.
# shellcheck disable=SC1090
os_info="$(. "$OS_RELEASE_FILE"; printf '%s %s' "${ID:-}" "${VERSION_ID:-}")"
case "$os_info" in
  'ubuntu 22.04'|'ubuntu 24.04'|'ubuntu 26.04') ;;
  *)
    if [[ -f "$CONF" ]]; then
      echo "Warning: $os_info is not a tested Ubuntu LTS release; refreshing an existing installation." >&2
    else
      echo "Unsupported OS: $os_info. Fresh installations require Ubuntu 22.04, 24.04, or 26.04 LTS." >&2
      exit 1
    fi
    ;;
esac
if [[ ! -f "$CONF" ]]; then
  disk_path="$CS2_HOME"
  [[ ! -d "$CS2_DIR" ]] || disk_path="$CS2_DIR"
  available_kib="$(df -Pk "$disk_path" | awk 'END { print $4 }')"
  if [[ ! "$available_kib" =~ ^[0-9]+$ ]]; then
    echo "Could not determine free disk space at $disk_path." >&2
    exit 1
  fi
  if (( available_kib < 60 * 1024 * 1024 )); then
    echo 'At least 60 GiB free disk space is needed before downloading CS2.' >&2
    exit 1
  fi
  if (( available_kib < 85 * 1024 * 1024 )); then
    echo 'Warning: less than 85 GiB free; the game download and future updates may need more space.' >&2
  fi
fi

command -v sudo >/dev/null 2>&1 || { echo 'sudo is required for installation.' >&2; exit 1; }
command -v apt-get >/dev/null 2>&1 || { echo 'apt-get is required for installation.' >&2; exit 1; }

sudo apt-get update
sudo apt-get install -y curl ca-certificates lib32gcc-s1 lib32stdc++6 git util-linux python3 unzip iproute2 procps
for required in curl tar python3 flock systemctl ip pgrep; do
  command -v "$required" >/dev/null 2>&1 || { echo "Missing required command after package installation: $required" >&2; exit 1; }
done

# Existing installations keep their exact launch binding and RCON defaults.
# A fresh server behind NAT must listen on a local address, not its public IP.
if [[ ! -f "$CONF" ]]; then
  local_ipv4="$(ip -o -4 addr show | awk '$3 == "inet" { split($4, address, "/"); print address[1] }')"
  if [[ -z "$BIND_IP" ]]; then
    if grep -Fxq -- "$HOST_IP" <<< "$local_ipv4"; then
      BIND_IP="$HOST_IP"
    else
      BIND_IP=0.0.0.0
      echo 'Public HOST_IP is not assigned locally; binding on all IPv4 interfaces for NAT hosting.'
      echo 'Forward the game UDP port from your router/provider to this machine.'
    fi
  elif [[ "$BIND_IP" != 0.0.0.0 ]] && ! grep -Fxq -- "$BIND_IP" <<< "$local_ipv4"; then
    echo "BIND_IP=$BIND_IP is not assigned to a local IPv4 interface." >&2
    exit 1
  fi
  if [[ -z "$RCON_HOST" ]]; then
    if [[ "$BIND_IP" == 0.0.0.0 ]]; then
      RCON_HOST=127.0.0.1
    else
      RCON_HOST="$BIND_IP"
    fi
  fi
fi

if [[ ! -x "$CS2_HOME/steamcmd/steamcmd.sh" ]]; then
  mkdir -p "$CS2_HOME/steamcmd"
  steamcmd_archive="$(mktemp "$CS2_HOME/steamcmd/.steamcmd.XXXXXXXX.tar.gz")"
  trap 'rm -f "$steamcmd_archive"' EXIT
  steamcmd_ready=0
  for attempt in 1 2 3; do
    if curl -fsSL --connect-timeout 15 --max-time 180 \
        -o "$steamcmd_archive" https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
        && tar -tzf "$steamcmd_archive" >/dev/null \
        && tar -xzf "$steamcmd_archive" -C "$CS2_HOME/steamcmd" \
        && [[ -x "$CS2_HOME/steamcmd/steamcmd.sh" ]]; then
      steamcmd_ready=1
      break
    fi
    echo "SteamCMD bootstrap failed (attempt $attempt/3)." >&2
    sleep "$attempt"
  done
  if [[ "$steamcmd_ready" != 1 ]]; then
    echo 'SteamCMD could not be downloaded and verified. Retry the installer after checking network access.' >&2
    exit 1
  fi
  rm -f "$steamcmd_archive"
  trap - EXIT
fi

mkdir -p "$CS2_DIR" "$UNIT_DIR" "$CS2_DIR/backups"
chmod 700 "$CS2_DIR/backups"
game_install_valid() {
  [[ -x "$CS2_DIR/game/bin/linuxsteamrt64/cs2" ]] \
    && [[ -s "$CS2_DIR/steamapps/appmanifest_730.acf" ]] \
    && grep -Eq '"buildid"[[:space:]]+"[0-9]+"' "$CS2_DIR/steamapps/appmanifest_730.acf"
}
if ! game_install_valid; then
  game_ready=0
  for attempt in 1 2 3; do
    if "$CS2_HOME/steamcmd/steamcmd.sh" +force_install_dir "$CS2_DIR" +login anonymous +app_update 730 validate +quit \
        && game_install_valid; then
      game_ready=1
      break
    fi
    echo "CS2 download did not pass validation (attempt $attempt/3)." >&2
    sleep "$attempt"
  done
  if [[ "$game_ready" != 1 ]]; then
    echo 'CS2 did not install correctly. SteamCMD can be rerun by executing the installer again.' >&2
    exit 1
  fi
else
  echo "Game already installed; use cs2-safe-update.sh for game updates."
fi

install -m 0755 "$REPO_DIR/scripts/cs2-admin.sh" "$CS2_DIR/cs2-admin.sh"
install -m 0755 "$REPO_DIR/scripts/cs2-workshop.py" "$CS2_DIR/cs2-workshop.py"
install -m 0755 "$REPO_DIR/scripts/cs2-config.sh" "$CS2_DIR/cs2-config.sh"
install -m 0755 "$REPO_DIR/scripts/cs2-rcon.py" "$CS2_DIR/cs2-rcon.py"
install -m 0755 "$REPO_DIR/scripts/cs2-buildid.py" "$CS2_DIR/cs2-buildid.py"
install -m 0755 "$REPO_DIR/scripts/cs2-health.sh" "$CS2_DIR/cs2-health.sh"
install -m 0755 "$REPO_DIR/scripts/cs2-safe-update.sh" "$CS2_DIR/cs2-safe-update.sh"
install -m 0755 "$REPO_DIR/scripts/cs2-daily-home.sh" "$CS2_DIR/cs2-daily-home.sh"
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
    for field in HOST_IP BIND_IP RCON_HOST PORT RCON_PASS SERVER_NAME SERVER_PASS GSLT; do
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
      'mp_halftime_pausetimer 0' 'mp_overtime_enable 1' 'mp_overtime_maxrounds 6' \
      'mp_overtime_halftime_pausetimer 0' 'mp_freezetime 15' \
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
install -m 0644 "$REPO_DIR/systemd/cs2-daily-home.service" "$UNIT_DIR/cs2-daily-home.service"
install -m 0644 "$REPO_DIR/systemd/cs2-daily-home.timer" "$UNIT_DIR/cs2-daily-home.timer"

sudo loginctl enable-linger "$CS2_USER"
systemctl --user daemon-reload
systemctl --user enable --now cs2-ds.service
systemctl --user enable --now cs2-daily-home.timer

# Root-owned maintenance avoids granting the game account passwordless apt or
# reboot privileges. Replace Ubuntu's floating apt timers with the player-safe
# morning window. The script invokes the user's RCON helper only as that user.
# Capture the original apt timer state before enabling toolkit maintenance.
# Older toolkit deployments have already disabled apt timers, so their current
# state must never be mistaken for the state that preceded the toolkit.
sudo bash -c '
  set -euo pipefail
  state_dir=/var/lib/cs2-toolkit
  marker="$state_dir/apt-timers.pre-toolkit"
  install -d -m 0700 "$state_dir"
  exec 9>"$state_dir/apt-timers.lock"
  chmod 0600 "$state_dir/apt-timers.lock"
  flock 9
  if [[ ! -e "$marker" ]]; then
    if [[ -e /etc/systemd/system/cs2-os-maintenance@.timer ]]; then
      echo "Warning: previous toolkit OS maintenance found; original apt timer state is unknown and will not be recorded." >&2
    else
      temporary="$(mktemp "$state_dir/.apt-timers.XXXXXXXX")"
      for timer in apt-daily.timer apt-daily-upgrade.timer; do
        state="$(systemctl is-enabled "$timer" 2>/dev/null || true)"
        if [[ "$state" == enabled || "$state" == enabled-runtime ]]; then
          printf "%s\n" "$timer" >> "$temporary"
        fi
      done
      chmod 0600 "$temporary"
      mv -n "$temporary" "$marker"
      rm -f "$temporary"
    fi
  fi
'
sudo install -m 0755 "$REPO_DIR/scripts/cs2-os-maintenance.sh" /usr/local/sbin/cs2-os-maintenance.sh
sudo install -m 0644 "$REPO_DIR/systemd/cs2-os-maintenance@.service" /etc/systemd/system/cs2-os-maintenance@.service
sudo install -m 0644 "$REPO_DIR/systemd/cs2-os-maintenance@.timer" /etc/systemd/system/cs2-os-maintenance@.timer
sudo systemctl daemon-reload
sudo systemctl enable --now "cs2-os-maintenance@${CS2_USER}.timer"
sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer
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
