#!/bin/bash
# CS2 dedicated server launcher for systemd user service
set -uo pipefail

BASE_DIR="/home/CS2USER/cs2-ds"
BIN_DIR="$BASE_DIR/game/bin/linuxsteamrt64"
CFG_NAME="cs2server.cfg"

IP="0.0.0.0"
PORT="27015"
MAXPLAYERS="32"
DEFAULT_MAP="de_dust2"

cd "$BIN_DIR"

exec "$BIN_DIR/cs2" \
  -dedicated \
  -usercon \
  -ip "$IP" \
  -port "$PORT" \
  -maxplayers "$MAXPLAYERS" \
  +map "$DEFAULT_MAP" \
  +exec "$CFG_NAME" \
  -console
