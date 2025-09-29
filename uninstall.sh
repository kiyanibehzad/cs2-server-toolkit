#!/bin/bash
set -euo pipefail
CS2_USER="${CS2_USER:-cs2server}"
CS2_HOME="/home/$CS2_USER"
UNIT_DIR="$CS2_HOME/.config/systemd/user"

systemctl --user disable --now cs2-checkupdate.timer 2>/dev/null || true
systemctl --user disable --now cs2-update.timer 2>/dev/null || true
systemctl --user disable --now cs2-ds 2>/dev/null || true
rm -f "$UNIT_DIR/cs2-checkupdate."{service,timer} \
      "$UNIT_DIR/cs2-update."{service,timer} \
      "$UNIT_DIR/cs2-ds.service" "$UNIT_DIR/cs2-ds.env" \
      "$CS2_HOME/admin-cs2"
systemctl --user daemon-reload
echo "Uninstalled systemd units. Game data is preserved in $CS2_HOME/cs2-ds"
