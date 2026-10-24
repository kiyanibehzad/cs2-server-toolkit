#!/bin/bash
set -euo pipefail
CS2_HOME="$HOME"
[[ "$(id -u)" -ne 0 ]] || { echo "Run as the game user, not root." >&2; exit 1; }
UNIT_DIR="$CS2_HOME/.config/systemd/user"
CS2_USER="$(id -un)"
ROOT_TIMER="cs2-os-maintenance@${CS2_USER}.timer"
ROOT_SERVICE="cs2-os-maintenance@${CS2_USER}.service"
APT_TIMER_STATE=/var/lib/cs2-toolkit/apt-timers.pre-toolkit

# Do not terminate apt/dpkg in the middle of a package transaction.
sudo -v
if ! root_state="$(sudo systemctl show "$ROOT_SERVICE" -p ActiveState --value 2>/dev/null)"; then
  echo "Could not verify $ROOT_SERVICE state; uninstall deferred." >&2
  exit 1
fi
case "$root_state" in
  active|activating|reloading|deactivating)
    echo "OS maintenance is running; retry uninstall after it finishes." >&2
    exit 1
    ;;
esac
sudo systemctl disable --now "$ROOT_TIMER" 2>/dev/null || true
if sudo systemctl is-enabled --quiet "$ROOT_TIMER"; then
  echo "Could not disable $ROOT_TIMER." >&2
  exit 1
fi
sudo rm -f "/var/lib/cs2-toolkit/os-${CS2_USER}-updated.txt" \
  "/var/lib/cs2-toolkit/os-${CS2_USER}-indexes.txt"

# Stop this account's game before Ubuntu's apt timers can be restored. An
# enabled apt timer may run immediately when it is started again.
systemctl --user disable --now cs2-checkupdate.timer 2>/dev/null || true
systemctl --user disable --now cs2-update.timer 2>/dev/null || true
systemctl --user disable --now cs2-daily-home.timer 2>/dev/null || true
systemctl --user disable --now cs2-ds.service 2>/dev/null || true
game_state="$(systemctl --user show cs2-ds.service -p ActiveState --value 2>/dev/null)" || {
  echo 'Cannot verify that the CS2 service stopped; apt timers were not restored.' >&2
  exit 1
}
case "$game_state" in
  inactive|failed) ;;
  *) echo "CS2 service state is $game_state; apt timers were not restored." >&2; exit 1 ;;
esac

# The root-owned template can be shared by more than one game account. Restore
# Ubuntu's apt timers only when no toolkit OS maintenance instance remains.
if [[ -z "$(sudo find /etc/systemd/system -type l -name 'cs2-os-maintenance@*.timer' -print -quit)" ]]; then
  sudo rm -f /etc/systemd/system/cs2-os-maintenance@.service \
    /etc/systemd/system/cs2-os-maintenance@.timer \
    /usr/local/sbin/cs2-os-maintenance.sh
  sudo systemctl daemon-reload
  if sudo test -f "$APT_TIMER_STATE"; then
    while IFS= read -r timer; do
      case "$timer" in
        apt-daily.timer|apt-daily-upgrade.timer)
          sudo systemctl enable --now "$timer"
          ;;
      esac
    done <<< "$(sudo cat "$APT_TIMER_STATE")"
    sudo rm -f "$APT_TIMER_STATE"
  else
    echo "Previous apt timer state is unknown; inspect apt-daily timers manually." >&2
  fi
fi

rm -f "$UNIT_DIR/cs2-checkupdate."{service,timer} \
      "$UNIT_DIR/cs2-update."{service,timer} \
      "$UNIT_DIR/cs2-daily-home."{service,timer} \
      "$UNIT_DIR/cs2-ds.service" "$UNIT_DIR/cs2-ds.env"
if [[ -L "$CS2_HOME/admin-cs2" ]] &&
   [[ "$(readlink "$CS2_HOME/admin-cs2")" == "$CS2_HOME/cs2-ds/cs2-admin.sh" ]]; then
  rm -f "$CS2_HOME/admin-cs2"
fi
if [[ -L "$CS2_HOME/update-cs2.sh" ]] &&
   [[ "$(readlink "$CS2_HOME/update-cs2.sh")" == "$CS2_HOME/cs2-ds/update-cs2.sh" ]]; then
  rm -f "$CS2_HOME/update-cs2.sh"
fi
systemctl --user daemon-reload
echo "Uninstalled CS2 toolkit services and timers. Game data is preserved in $CS2_HOME/cs2-ds"
