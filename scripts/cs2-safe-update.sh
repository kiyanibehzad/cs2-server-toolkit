#!/usr/bin/env bash
set -euo pipefail

# All scheduled and manual game updates go through this script. --force skips
# the build-ID comparison, but never bypasses the player check.
MODE="${1:---check}"
case "$MODE" in
  --check|--force) ;;
  *) echo "Usage: $0 [--check|--force]" >&2; exit 2 ;;
esac

CS2_HOME="${CS2_HOME:-$HOME}"
CS2_DIR="${CS2_DIR:-$CS2_HOME/cs2-ds}"
STEAMCMD="${STEAMCMD:-$CS2_HOME/steamcmd/steamcmd.sh}"
UNIT="${SERVICE_NAME:-cs2-ds}"
APP=730
LOG="$CS2_DIR/update.log"
MAX_UPDATE_TRIES=3

umask 077
mkdir -p "$CS2_DIR"
log() { printf '[safe-update] %s %s\n' "$(date -Is)" "$*" | tee -a "$LOG"; }

[[ -x "$STEAMCMD" ]] || { log "SteamCMD missing: $STEAMCMD"; exit 127; }
command -v flock >/dev/null || { log "flock is required"; exit 127; }

exec 9>"$CS2_DIR/.update.lock"
flock -n 9 || { log "another update is in progress; skipping"; exit 0; }

local_buildid() {
  local manifest="$CS2_DIR/steamapps/appmanifest_${APP}.acf"
  [[ -f "$manifest" ]] || return 1
  awk -F'"' '/"buildid"/{print $4; exit}' "$manifest"
}

remote_buildid() {
  "$STEAMCMD" +login anonymous +app_info_update 1 +app_info_print "$APP" +quit \
    | tr -d '\r' | awk -F'"' '/"buildid"/{print $4; exit}'
}

# Return 0 when empty, 1 when occupied, and 2 when status cannot be trusted.
players_empty() {
  local host port pass output humans
  [[ -r "$CS2_DIR/.update.env" ]] || return 2
  # shellcheck disable=SC1091
  . "$CS2_DIR/.update.env"
  host="${HOST_IP:-127.0.0.1}"
  port="${PORT:-27015}"
  pass="${RCON_PASS:-}"
  [[ -n "$pass" ]] && command -v mcrcon >/dev/null || return 2
  output="$(mcrcon -H "$host" -P "$port" -p "$pass" status 2>/dev/null)" || return 2
  humans="$(printf '%s\n' "$output" | awk -F'[, ]+' '/^players[[:space:]]*:/ {print $3; exit}')"
  [[ "$humans" =~ ^[0-9]+$ ]] || return 2
  (( humans == 0 ))
}

update_game() {
  local attempt
  for ((attempt=1; attempt<=MAX_UPDATE_TRIES; attempt++)); do
    log "SteamCMD attempt $attempt/$MAX_UPDATE_TRIES"
    if "$STEAMCMD" +force_install_dir "$CS2_DIR" +login anonymous +app_update "$APP" validate +quit; then
      return 0
    fi
    (( attempt < MAX_UPDATE_TRIES )) && sleep 3
  done
  return 1
}

# The EXIT trap restores a server that was running before the update, even
# when SteamCMD fails. A server that was already stopped remains stopped.
restart_needed=0
restore_server() {
  local result=$?
  trap - EXIT
  if (( restart_needed )); then
    if systemctl --user start "$UNIT"; then
      log "server started"
    else
      log "ERROR: server could not be started"
      result=1
    fi
  fi
  exit "$result"
}
trap restore_server EXIT

if [[ "$MODE" == --check ]]; then
  remote=""
  for attempt in 1 2 3; do
    remote="$(remote_buildid || true)"
    [[ "$remote" =~ ^[0-9]+$ ]] && break
    sleep 2
  done
  [[ "$remote" =~ ^[0-9]+$ ]] || { log "remote build ID unavailable; skipping"; exit 1; }
  localb="$(local_buildid || true)"
  log "local=${localb:-unknown} remote=$remote"
  if [[ -n "$localb" && "$localb" == "$remote" ]]; then
    log "up to date"
    exit 0
  fi
fi

state="$(systemctl --user show "$UNIT" -p ActiveState --value 2>/dev/null)" || {
  log "cannot query server service; skipping"
  exit 1
}
case "$state" in
  active)
    if players_empty; then
      log "server is empty"
    else
      result=$?
      if (( result == 1 )); then
        log "players detected; deferring update"
        exit 0
      fi
      log "RCON status unknown; deferring update"
      exit 1
    fi
    restart_needed=1
    log "stopping server"
    systemctl --user stop "$UNIT" || { log "failed to stop server"; exit 1; }
    ;;
  inactive|failed)
    log "server was already stopped"
    ;;
  *)
    log "server state '$state' is not safe for update; skipping"
    exit 1
    ;;
esac

if update_game; then
  log "game update succeeded"
else
  log "game update failed; restoring previous server state"
  exit 1
fi
