#!/bin/bash
set -euo pipefail
CS2_HOME="$HOME"
[[ "$(id -u)" -ne 0 ]] || { echo "Run as the game user, not root." >&2; exit 1; }
UNIT_DIR="$CS2_HOME/.config/systemd/user"

systemctl --user disable --now cs2-checkupdate.timer 2>/dev/null || true
systemctl --user disable --now cs2-update.timer 2>/dev/null || true
systemctl --user disable --now cs2-ds 2>/dev/null || true
rm -f "$UNIT_DIR/cs2-checkupdate."{service,timer} \
      "$UNIT_DIR/cs2-update."{service,timer} \
      "$UNIT_DIR/cs2-ds.service" "$UNIT_DIR/cs2-ds.env" \
      "$CS2_HOME/admin-cs2" "$CS2_HOME/update-cs2.sh"
systemctl --user daemon-reload
echo "Uninstalled systemd units. Game data is preserved in $CS2_HOME/cs2-ds"
