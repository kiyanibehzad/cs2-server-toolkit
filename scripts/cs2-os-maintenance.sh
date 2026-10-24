#!/usr/bin/env bash
# Root-owned, player-safe Ubuntu package updates and conditional reboot.
set -euo pipefail

[[ "$(id -u)" == 0 ]] || { echo 'Run as root' >&2; exit 1; }
user="${1:-}"
[[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo 'Invalid game user' >&2; exit 2; }
home="$(getent passwd "$user" | cut -d: -f6)"
[[ "$home" == /* && -d "$home" ]] || { echo 'Game user home missing' >&2; exit 1; }
dir="$home/cs2-ds"
[[ -x "$dir/cs2-admin.sh" ]] || { echo 'CS2 admin helper missing' >&2; exit 1; }

# Package operations are supported here only on the apt-based server profile.
# shellcheck disable=SC1091
. /etc/os-release
[[ "$ID" == ubuntu || "$ID" == debian ]] || { echo 'Unsupported OS' >&2; exit 1; }

hour="$(date +%H)"
(( 10#$hour >= 6 && 10#$hour < 12 )) || exit 0
today="$(date +%F)"
state_dir=/var/lib/cs2-toolkit
mkdir -p "$state_dir"
done_file="$state_dir/os-${user}-updated.txt"
indexes_file="$state_dir/os-${user}-indexes.txt"

# Share the game updater lock. Create it as the game user if absent so future
# game updates can still open it without root ownership problems.
if [[ ! -e "$dir/.update.lock" ]]; then
  runuser -u "$user" -- touch "$dir/.update.lock"
fi
[[ ! -L "$dir/.update.lock" ]] || { echo 'Refusing symlink lock' >&2; exit 1; }
exec 9<>"$dir/.update.lock"
flock -n 9 || { echo 'Game maintenance in progress; retrying later'; exit 0; }

players_empty() {
  local output humans
  output="$(runuser -u "$user" -- env HOME="$home" CS2_DIR="$dir" "$dir/cs2-admin.sh" rcon status 2>/dev/null)" || return 2
  humans="$(printf '%s\n' "$output" | sed -nE 's/^[[:space:]]*players[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]+humans,.*/\1/p' | head -n 1)"
  [[ "$humans" =~ ^[0-9]+$ ]] || return 2
  (( humans == 0 ))
}

# An unavailable RCON response does not mean the game is empty. If the game
# process is absent, however, package changes cannot interrupt its players.
game_process_absent() {
  local result=0
  command -v pgrep >/dev/null 2>&1 || return 1
  pgrep -u "$user" -x cs2 >/dev/null 2>&1 || result=$?
  (( result == 1 ))
}

game_service_idle() {
  local uid state
  uid="$(id -u "$user")" || return 1
  state="$(runuser -u "$user" -- env HOME="$home" \
    XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    systemctl --user show cs2-ds.service -p ActiveState --value 2>/dev/null)" || return 1
  [[ "$state" == inactive || "$state" == failed ]]
}

safe_for_package_changes() {
  local result=0
  players_empty || result=$?
  case "$result" in
    0) return 0 ;;
    1) echo 'Players online; package changes deferred'; return 1 ;;
    2)
      if game_process_absent && game_service_idle; then
        echo 'RCON unavailable; CS2 service is idle and no game process exists'
        return 0
      fi
      echo 'RCON unavailable and game process or service may be running; package changes deferred'
      return 1
      ;;
  esac
  return 1
}

# Refresh package indexes even when players are present or RCON is unavailable.
# apt-get update only fetches metadata; it does not install packages or reboot.
if [[ "$(cat "$indexes_file" 2>/dev/null || true)" != "$today" ]]; then
  apt-get -o DPkg::Lock::Timeout=600 update
  printf '%s\n' "$today" > "$indexes_file"
  echo 'OS package indexes refreshed'
fi

safe_for_package_changes || exit 0

if [[ "$(cat "$done_file" 2>/dev/null || true)" != "$today" ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold --with-new-pkgs upgrade -y
  printf '%s\n' "$today" > "$done_file"
  echo 'OS packages updated'
fi

if [[ -f /run/reboot-required ]]; then
  if safe_for_package_changes; then
    echo 'Reboot required; rebooting empty server'
    systemctl reboot
  else
    echo 'Reboot required; players online or status unavailable, retrying later'
  fi
else
  echo 'No reboot required'
fi
