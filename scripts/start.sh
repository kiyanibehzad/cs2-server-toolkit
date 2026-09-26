#!/bin/bash
# CS2 dedicated server launcher for systemd user service
set -uo pipefail

BASE_DIR="${CS2_DIR:-${HOME}/cs2-ds}"
BIN_DIR="$BASE_DIR/game/bin/linuxsteamrt64"
CFG_NAME="cs2server.cfg"

CONF="$BASE_DIR/.update.env"
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && . "$CONF"
"$BASE_DIR/cs2-config.sh" sync || exit 1
if [[ -x "$BASE_DIR/cs2-ingame-menu.sh" ]]; then
  "$BASE_DIR/cs2-ingame-menu.sh" repair-loader || echo '[cs2-start] In-game menu loader repair failed; check the plugin installation.' >&2
fi

IP="${BIND_IP:-${HOST_IP:-0.0.0.0}}"
PORT="${PORT:-27015}"
MAXPLAYERS="${MAXPLAYERS:-32}"
DEFAULT_MAP="${DEFAULT_MAP:-de_dust2}"

cd "$BIN_DIR" || exit 1

# .update.env is the only toolkit source for the game server login token.
args=(-dedicated -usercon -ip "$IP" -port "$PORT" -maxplayers "$MAXPLAYERS")
[[ -n "${GSLT:-}" ]] && args+=(+sv_setsteamaccount "$GSLT")
args+=(+game_type 0 +game_mode 1 +map "$DEFAULT_MAP" +exec "$CFG_NAME" -console)
exec "$BIN_DIR/cs2" "${args[@]}"
