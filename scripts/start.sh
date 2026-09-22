#!/bin/bash
# CS2 dedicated server launcher for systemd user service
set -uo pipefail

BASE_DIR="${CS2_DIR:-${HOME}/cs2-ds}"
BIN_DIR="$BASE_DIR/game/bin/linuxsteamrt64"
CFG_NAME="cs2server.cfg"

CONF="$BASE_DIR/.update.env"
[[ -f "$CONF" ]] && . "$CONF"

IP="${BIND_IP:-${HOST_IP:-0.0.0.0}}"
PORT="${PORT:-27015}"
MAXPLAYERS="${MAXPLAYERS:-32}"
DEFAULT_MAP="${DEFAULT_MAP:-de_dust2}"

cd "$BIN_DIR"

# The token is also in cs2server.cfg. Keep the launch argument for existing
# installations that rely on registering before the map loads.
args=(-dedicated -usercon -ip "$IP" -port "$PORT" -maxplayers "$MAXPLAYERS")
[[ -n "${GSLT:-}" ]] && args+=(+sv_setsteamaccount "$GSLT")
args+=(+map "$DEFAULT_MAP" +exec "$CFG_NAME" -console)
exec "$BIN_DIR/cs2" "${args[@]}"
