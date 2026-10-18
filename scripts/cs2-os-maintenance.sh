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
  humans="$(printf '%s\n' "$output" | sed -nE 's/^[[:space:]]*players[[:space:]]*:[[:space:]]*([0-9]+) humans,.*/\1/p' | head -n 1)"
  [[ "$humans" =~ ^[0-9]+$ ]] || return 2
  (( humans == 0 ))
}

if ! players_empty; then
  echo 'Players online or status unavailable; OS maintenance deferred'
  exit 0
fi

if [[ "$(cat "$done_file" 2>/dev/null || true)" != "$today" ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get -o DPkg::Lock::Timeout=600 update
  apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold --with-new-pkgs upgrade -y
  printf '%s\n' "$today" > "$done_file"
  echo 'OS packages updated'
fi

if [[ -f /run/reboot-required ]]; then
  if players_empty; then
    echo 'Reboot required; rebooting empty server'
    systemctl reboot
  else
    echo 'Reboot required; players online or status unavailable, retrying later'
  fi
else
  echo 'No reboot required'
fi
