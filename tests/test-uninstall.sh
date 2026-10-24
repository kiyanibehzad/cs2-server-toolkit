#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/home/.config/systemd/user" \
  "$TEST_ROOT/home/cs2-ds" "$TEST_ROOT/etc/systemd/system/timers.target.wants" \
  "$TEST_ROOT/usr/local/sbin" "$TEST_ROOT/var/lib/cs2-toolkit"

sed -e "s@/etc/systemd/system@$TEST_ROOT/etc/systemd/system@g" \
  -e "s@/usr/local/sbin/cs2-os-maintenance.sh@$TEST_ROOT/usr/local/sbin/cs2-os-maintenance.sh@g" \
  -e "s@/var/lib/cs2-toolkit@$TEST_ROOT/var/lib/cs2-toolkit@g" \
  "$REPO/uninstall.sh" > "$TEST_ROOT/uninstall.sh"

cat > "$TEST_ROOT/bin/id" <<'EOF'
#!/usr/bin/env bash
case "$1" in -u) echo 1000 ;; -un) echo cs2server ;; esac
EOF
cat > "$TEST_ROOT/bin/sudo" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -v ]] && exit 0
"$@"
EOF
cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$EVENTS"
if [[ "$1" == show || ( "$1" == --user && "$2" == show ) ]]; then
  if [[ -f "$TEST_ROOT/root-service-active" ]]; then
    echo activating
  else
    echo inactive
  fi
  exit 0
fi
[[ "$1" == is-enabled ]] && exit 1
if [[ "$1" == disable && "$2" == --now && "$3" == cs2-os-maintenance@cs2server.timer ]]; then
  rm -f "$TEST_ROOT/etc/systemd/system/timers.target.wants/$3"
fi
EOF
chmod +x "$TEST_ROOT/bin/"*
export HOME="$TEST_ROOT/home" TEST_ROOT EVENTS="$TEST_ROOT/events" PATH="$TEST_ROOT/bin:$PATH"

root_units() {
  touch "$TEST_ROOT/etc/systemd/system/cs2-os-maintenance@.service" \
    "$TEST_ROOT/etc/systemd/system/cs2-os-maintenance@.timer" \
    "$TEST_ROOT/usr/local/sbin/cs2-os-maintenance.sh"
  ln -s "$TEST_ROOT/etc/systemd/system/cs2-os-maintenance@.timer" \
    "$TEST_ROOT/etc/systemd/system/timers.target.wants/cs2-os-maintenance@cs2server.timer"
}

root_units
printf 'apt-daily.timer\napt-daily-upgrade.timer\n' > "$TEST_ROOT/var/lib/cs2-toolkit/apt-timers.pre-toolkit"
touch "$TEST_ROOT/home/.config/systemd/user/cs2-daily-home.service" \
  "$TEST_ROOT/home/.config/systemd/user/cs2-daily-home.timer"
ln -s "$HOME/cs2-ds/cs2-admin.sh" "$HOME/admin-cs2"
ln -s "$HOME/cs2-ds/update-cs2.sh" "$HOME/update-cs2.sh"

touch "$TEST_ROOT/root-service-active"
if bash "$TEST_ROOT/uninstall.sh" > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL uninstalled while package maintenance was active' >&2
  exit 1
fi
[[ -e "$TEST_ROOT/etc/systemd/system/cs2-os-maintenance@.timer" ]]
rm -f "$TEST_ROOT/root-service-active"

# Keep shared root files and the apt marker while another game account still
# has an enabled toolkit maintenance timer.
ln -s "$TEST_ROOT/etc/systemd/system/cs2-os-maintenance@.timer" \
  "$TEST_ROOT/etc/systemd/system/timers.target.wants/cs2-os-maintenance@other.timer"
bash "$TEST_ROOT/uninstall.sh" > "$TEST_ROOT/output" 2>&1
[[ -e "$TEST_ROOT/etc/systemd/system/cs2-os-maintenance@.timer" ]]
[[ -e "$TEST_ROOT/var/lib/cs2-toolkit/apt-timers.pre-toolkit" ]]
if grep -q 'enable --now apt-daily' "$EVENTS"; then
  echo 'FAIL restored apt timers while another game user remains' >&2
  exit 1
fi
rm -f "$TEST_ROOT/etc/systemd/system/timers.target.wants/cs2-os-maintenance@other.timer"
root_units
: > "$EVENTS"

bash "$TEST_ROOT/uninstall.sh" > "$TEST_ROOT/output" 2>&1
[[ ! -e "$TEST_ROOT/etc/systemd/system/cs2-os-maintenance@.timer" ]]
[[ ! -e "$TEST_ROOT/usr/local/sbin/cs2-os-maintenance.sh" ]]
[[ ! -e "$TEST_ROOT/var/lib/cs2-toolkit/apt-timers.pre-toolkit" ]]
[[ ! -e "$HOME/.config/systemd/user/cs2-daily-home.timer" ]]
[[ ! -e "$HOME/admin-cs2" && ! -e "$HOME/update-cs2.sh" ]]
grep -Fxq 'enable --now apt-daily.timer' "$EVENTS"
grep -Fxq 'enable --now apt-daily-upgrade.timer' "$EVENTS"
grep -Fxq -- '--user disable --now cs2-daily-home.timer' "$EVENTS"
game_stop_line="$(grep -nF -- '--user disable --now cs2-ds.service' "$EVENTS" | tail -n 1 | cut -d: -f1)"
apt_restore_line="$(grep -nF 'enable --now apt-daily.timer' "$EVENTS" | tail -n 1 | cut -d: -f1)"
[[ -n "$game_stop_line" && -n "$apt_restore_line" && "$game_stop_line" -lt "$apt_restore_line" ]] || {
  echo 'FAIL restored apt timers before stopping CS2' >&2
  exit 1
}
echo 'PASS uninstall_restores_prior_apt_timer_state_after_last_game_user'

# Legacy installs have no saved pre-toolkit state. Leave apt timers as they are.
: > "$EVENTS"
root_units
bash "$TEST_ROOT/uninstall.sh" > "$TEST_ROOT/output" 2>&1
if grep -q 'enable --now apt-daily' "$EVENTS"; then
  echo 'FAIL restored apt timers without a saved prior state' >&2
  exit 1
fi
grep -Fq 'Previous apt timer state is unknown' "$TEST_ROOT/output"
echo 'PASS uninstall_does_not_guess_legacy_apt_timer_state'
