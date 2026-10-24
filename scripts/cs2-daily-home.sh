#!/usr/bin/env bash
# At the first empty moment between 06:00 and noon, restart once and load Home.
set -euo pipefail

CS2_DIR="${CS2_DIR:-$HOME/cs2-ds}"
UNIT="${SERVICE_NAME:-cs2-ds}"
CONF="$CS2_DIR/.update.env"
[[ -r "$CONF" ]] || { echo '[daily-home] missing server settings' >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONF"
UNIT="${SERVICE_NAME:-$UNIT}"

hour="$(date +%H)"
(( 10#$hour >= 6 && 10#$hour < 12 )) || exit 0
today="$(date +%F)"
STATE_DIR="$CS2_DIR/toolkit-config"
mkdir -p "$STATE_DIR"
done_file="$STATE_DIR/daily-home-done.txt"
restart_file="$STATE_DIR/daily-home-restarted.txt"
[[ "$(cat "$done_file" 2>/dev/null || true)" != "$today" ]] || exit 0

# The updater takes the same lock. Never restart during SteamCMD maintenance.
exec 9>"$CS2_DIR/.update.lock"
flock -n 9 || { echo '[daily-home] maintenance in progress; retrying later'; exit 0; }
[[ "$(cat "$done_file" 2>/dev/null || true)" != "$today" ]] || exit 0

players_empty() {
  local output humans host="${RCON_HOST:-${HOST_IP:-127.0.0.1}}" port="${PORT:-27015}"
  [[ -n "${RCON_PASS:-}" ]] || return 2
  [[ -x "$CS2_DIR/cs2-rcon.py" ]] || return 2
  output="$(RCON_PASS="$RCON_PASS" "$CS2_DIR/cs2-rcon.py" -H "$host" -P "$port" status 2>/dev/null)" || return 2
  humans="$(printf '%s\n' "$output" | sed -nE 's/^[[:space:]]*players[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]+humans,.*/\1/p' | head -n 1)"
  [[ "$humans" =~ ^[0-9]+$ ]] || return 2
  (( humans == 0 ))
}

if systemctl --user is-active --quiet "${UNIT}.service"; then
  if players_empty; then
    :
  else
    result=$?
    if (( result == 1 )); then
      echo '[daily-home] players online; retrying in five minutes'
    else
      echo '[daily-home] player status unavailable; refusing to interrupt the server' >&2
    fi
    exit 0
  fi
fi

if [[ "$(cat "$restart_file" 2>/dev/null || true)" != "$today" ]]; then
  if systemctl --user is-active --quiet "${UNIT}.service"; then
    # Close the small check-to-restart gap with one more live player check.
    players_empty || { echo '[daily-home] player status changed; retrying later'; exit 0; }
    systemctl --user restart "${UNIT}.service"
  else
    systemctl --user start "${UNIT}.service"
  fi
  printf '%s\n' "$today" > "$restart_file"
  rm -f "$STATE_DIR/voice-baseline.txt"
fi

# The launcher defaults to competitive, but its map is configurable. Applying
# Home explicitly guarantees Competitive MR12 and de_dust2 each morning.
for ((attempt=1; attempt<=12; attempt++)); do
  if "$CS2_DIR/cs2-admin.sh" rcon status >/dev/null 2>&1; then break; fi
  sleep 5
done
players_empty || { echo '[daily-home] server not ready or a player joined; Home deferred'; exit 0; }
"$CS2_DIR/cs2-admin.sh" default
printf '%s\n' "$today" > "$done_file"
echo '[daily-home] Home preset applied'
