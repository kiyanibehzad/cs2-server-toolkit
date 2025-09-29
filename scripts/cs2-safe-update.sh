#!/bin/bash
# Safe updater for CS2 dedicated server (no mid-game restart)
set -euo pipefail

CS2_USER="CS2USER"
CS2_HOME="/home/$CS2_USER"
CS2_DIR="$CS2_HOME/cs2-ds"
SERVICE_NAME="cs2-ds"
STEAMCMD="$CS2_HOME/steamcmd/steamcmd.sh"
APPID="730"
MANIFEST="$CS2_DIR/steamapps/appmanifest_${APPID}.acf"
PENDING_FLAG="$CS2_DIR/.pending_update"
CONF="$CS2_DIR/.update.env"; [[ -f "$CONF" ]] && source "$CONF" || true
HOST_IP="${HOST_IP:-0.0.0.0}"
PORT="${PORT:-27015}"
RCON_PASS="${RCON_PASS:-ChangeMe123!}"

latest_buildid() {
  local out
  if [[ -x "$STEAMCMD" ]]; then
    out="$("$STEAMCMD" +login anonymous +app_info_update 1 +app_info_print "$APPID" +quit 2>/dev/null | tr -d '\r')"
  else
    out="$(steamcmd +login anonymous +app_info_update 1 +app_info_print "$APPID" +quit 2>/dev/null | tr -d '\r')"
  fi
  echo "$out" | awk -F\" '/"buildid"/{print $4; exit}'
}
local_buildid() { [[ -f "$MANIFEST" ]] && awk -F\" '/"buildid"/{print $4; exit}' "$MANIFEST" || echo "0"; }
player_count() {
  if command -v mcrcon >/dev/null 2>&1; then
    local s c
    s="$(mcrcon -H "$HOST_IP" -P "$PORT" -p "$RCON_PASS" status 2>/dev/null || true)"
    c="$(echo "$s" | awk '/players/ && /humans/{for(i=1;i<=NF;i++) if($i=="players"){print $(i+2); exit}}')"
    [[ "$c" =~ ^[0-9]+$ ]] || c=0; echo "$c"
  else echo 0; fi
}
stop_user_service() { systemctl --user stop "$SERVICE_NAME" || true; for i in {1..20}; do systemctl --user is-active --quiet "$SERVICE_NAME" || return 0; sleep 0.5; done; }
start_user_service(){ systemctl --user start "$SERVICE_NAME"; }
do_update_download_only(){ [[ -x "$STEAMCMD" ]] && "$STEAMCMD" +login anonymous +app_update "$APPID" +quit || steamcmd +login anonymous +app_update "$APPID" +quit; }
do_update_validate_full(){ [[ -x "$STEAMCMD" ]] && "$STEAMCMD" +login anonymous +app_update "$APPID" validate +quit || steamcmd +login anonymous +app_update "$APPID" validate +quit; }

LBLD="$(local_buildid)"; RBLD="$(latest_buildid || echo "0")"
echo "[safe-update] local=$LBLD remote=$RBLD"
[[ "$RBLD" == "0" ]] && { echo "[safe-update] WARN: cannot read remote buildid"; exit 0; }
[[ "$LBLD" == "$RBLD" && ! -f "$PENDING_FLAG" ]] && { echo "[safe-update] up-to-date"; exit 0; }

PCNT="$(player_count || echo 0)"; echo "[safe-update] players=$PCNT"
if [[ "$PCNT" -eq 0 ]]; then
  echo "[safe-update] applying update"
  rm -f "$PENDING_FLAG" || true
  stop_user_service
  do_update_validate_full
  start_user_service
  echo "[safe-update] done"
else
  echo "[safe-update] players online; downloading only"
  touch "$PENDING_FLAG" || true
  do_update_download_only
  echo "[safe-update] downloaded; restart deferred"
fi
