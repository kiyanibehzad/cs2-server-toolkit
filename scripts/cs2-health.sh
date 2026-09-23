#!/usr/bin/env bash
# Read-only diagnostics; never print credentials or a full process command line.
set -uo pipefail

CS2_DIR="${CS2_DIR:-$HOME/cs2-ds}"
STEAMCMD="${STEAMCMD:-$HOME/steamcmd/steamcmd.sh}"
SERVICE_NAME="${SERVICE_NAME:-cs2-ds}"
CONF="$CS2_DIR/.update.env"
# shellcheck disable=SC1090
[[ -r "$CONF" ]] && . "$CONF"
HOST="${HOST_IP:-127.0.0.1}"
PORT="${PORT:-27015}"
PASS="${RCON_PASS:-}"
report() { printf '%-19s %s\n' "$1" "$2"; }

state="$(systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || true)"
report Service "${state:-unavailable}"
pid="$(systemctl --user show "$SERVICE_NAME" -p MainPID --value 2>/dev/null || true)"
if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null; then
  report 'CS2 process' "running (PID $pid)"
else
  report 'CS2 process' 'not detected'
fi

if [[ -n "$PASS" && -x "$CS2_DIR/cs2-rcon.py" ]]; then
  if output="$(RCON_PASS="$PASS" "$CS2_DIR/cs2-rcon.py" -H "$HOST" -P "$PORT" status 2>/dev/null)"; then
    report RCON connected
    map="$(printf '%s\n' "$output" | sed -n 's/.*SV:  \[1: \([^ |]*\).*/\1/p' | head -n 1)"
    [[ -z "$map" ]] || report Map "$map"
  else
    report RCON unavailable
  fi
else
  report RCON 'unavailable (config/client missing)'
fi

if command -v ss >/dev/null 2>&1 && ss -H -lun 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$PORT$"; then
  report 'Game UDP port' "listening on $PORT"
else
  report 'Game UDP port' 'not detected'
fi

for file in "$CONF" "$CS2_DIR/game/csgo/cfg/cs2server.cfg" \
  "$CS2_DIR/game/bin/linuxsteamrt64/cs2" "$CS2_DIR/cs2-config.sh"; do
  if [[ ! -r "$file" ]]; then
    report 'Required file' "missing/unreadable: $file"
  fi
done
for file in "$CONF" "$CS2_DIR/game/csgo/cfg/cs2server.cfg"; do
  if [[ -e "$file" ]]; then
    mode="$(stat -c %a "$file" 2>/dev/null || true)"
    [[ "$mode" == 600 ]] || report Permissions "check $file (mode $mode)"
  fi
done

local_build="$(awk -F'"' '/"buildid"/{print $4; exit}' "$CS2_DIR/steamapps/appmanifest_730.acf" 2>/dev/null || true)"
report 'Installed build' "${local_build:-unknown}"
if [[ -x "$STEAMCMD" ]]; then
  remote_build="$("$STEAMCMD" +login anonymous +app_info_update 1 +app_info_print 730 +quit 2>/dev/null \
    | tr -d '\r' | python3 "$CS2_DIR/cs2-buildid.py" 2>/dev/null)"
  report 'Public build' "${remote_build:-unknown}"
  if [[ "$local_build" =~ ^[0-9]+$ && "$remote_build" =~ ^[0-9]+$ ]]; then
    [[ "$local_build" == "$remote_build" ]] && report Update current || report Update 'available or pending'
  fi
else
  report 'Public build' 'unavailable (SteamCMD missing)'
fi

if [[ -n "${GSLT:-}" ]]; then
  report GSLT 'configured (value hidden)'
else
  report GSLT 'not configured'
fi
report 'Steam/VAC login' 'not reliably exposed by this toolkit; inspect server journal'
