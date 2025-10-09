#!/usr/bin/env bash
set -euo pipefail

# --- paths & constants ---
USER_HOME="${HOME}"
CS2_DIR="${USER_HOME}/cs2-ds"
STEAMCMD="${USER_HOME}/steamcmd/steamcmd.sh"
LOG="${CS2_DIR}/update.log"
UNIT="cs2-ds"

APP=730                 # Use CS2 main app only
MAX_UPDATE_TRIES=3
RETRIES_APPINFO=5
SLEEP_BETWEEN_TRIES=3

ts()  { date -Is; }
log() { echo "[safe-update] $*" | tee -a "$LOG"; }

steamcmd_ok() { [[ -x "$STEAMCMD" ]]; }

reset_appinfo_cache() {
  rm -f  "${USER_HOME}/Steam/appcache/appinfo.vdf"  || true
  rm -rf "${USER_HOME}/Steam/appcache/httpcache"    || true
  "$STEAMCMD" +login anonymous +app_info_update 1 +quit >/dev/null || true
}

get_remote_buildid() {
  "$STEAMCMD" +login anonymous +app_info_update 1 +app_info_print "$APP" +quit \
    | tr -d '\r' \
    | awk -F\" '/"buildid"/{print $4; exit}' \
  || true
}

get_local_buildid() {
  local mf="${CS2_DIR}/steamapps/appmanifest_${APP}.acf"
  if [[ -f "$mf" ]]; then
    awk -F\" '/"buildid"/{print $4; exit}' "$mf" && return 0
  fi
  echo ""
}

# Consider server "busy" if there are human players > 0
server_is_busy() {
  if ! command -v mcrcon >/dev/null 2>&1; then
      return 1
  fi
  # Read RCON params from .update.env if present
  local host="127.0.0.1" port="27015" pass=""
  if [[ -f "${CS2_DIR}/.update.env" ]]; then
    # shellcheck disable=SC1090
    . "${CS2_DIR}/.update.env"
    host="${HOST_IP:-$host}"
    port="${PORT:-$port}"
    pass="${RCON_PASS:-$pass}"
  fi
  local out
  if [[ -n "$pass" ]]; then
    out="$(mcrcon -H "$host" -P "$port" -p "$pass" status 2>/dev/null || true)"
  else
    # If no RCON, assume not busy
    return 1
  fi
  # Parse "players  : X humans"
  local humans
  humans="$(echo "$out" | awk -F'[, ]+' '/^players[[:space:]]*:/{print $3; exit}' 2>/dev/null || echo "")"
  [[ -n "$humans" && "$humans" =~ ^[0-9]+$ && "$humans" -gt 0 ]]
}

stop_server() {
  systemctl --user stop "${UNIT}.service" || true
  sleep 2
}

start_server() {
  systemctl --user start "${UNIT}.service" || true
}

do_update() {
  local i=1
  while (( i <= MAX_UPDATE_TRIES )); do
    log "steamcmd attempt ${i}/${MAX_UPDATE_TRIES}..."
    if "$STEAMCMD" +login anonymous +app_update "$APP" validate +quit; then
      return 0
    fi
    (( i++ ))
    sleep "$SLEEP_BETWEEN_TRIES"
  done
  return 1
}

main() {
  mkdir -p "$(dirname "$LOG")"
  echo "[safe-update] ---- run $(ts) ----" >> "$LOG"

  if ! steamcmd_ok; then
    log "steamcmd not found at $STEAMCMD"
    exit 127
  fi

  # Get remote buildid with retries
  local remote=""
  for ((i=1; i<=RETRIES_APPINFO; i++)); do
    remote="$(get_remote_buildid)"
    [[ -n "$remote" ]] && break
    log "remote build empty; resetting appinfo cache and retrying (${i}/${RETRIES_APPINFO})..."
    reset_appinfo_cache
    sleep 1
  done
  if [[ -z "$remote" ]]; then
    log "cannot fetch remote buildid; skip"
    exit 0
  fi

  local localb=""
  localb="$(get_local_buildid || true)"
  log "local=${localb:-unknown} remote=${remote}"

  if [[ -n "$localb" && "$localb" == "$remote" ]]; then
    log "up-to-date"
    exit 0
  fi

  if server_is_busy; then
    log "players detected; skipping update for now"
    exit 0
  fi

  log "stopping server for update..."
  stop_server

  if do_update; then
    log "update OK; starting server..."
    start_server
    log "done"
    exit 0
  else
    log "steamcmd failed; starting server back and exiting with error"
    start_server
    exit 1
  fi
}

main "$@"
