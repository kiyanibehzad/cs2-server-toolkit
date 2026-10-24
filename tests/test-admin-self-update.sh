#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/home/.config/systemd/user" \
  "$TEST_ROOT/game" "$TEST_ROOT/root/sbin" "$TEST_ROOT/root/units"
printf 'RCON_PASS=keep-me\nHOST_IP=203.0.113.22\nRCON_HOST=127.0.0.1\n' > "$TEST_ROOT/game/.update.env"
cp "$TEST_ROOT/game/.update.env" "$TEST_ROOT/env.before"
cat > "$TEST_ROOT/reloaded-admin.sh" <<'EOF'
#!/usr/bin/env bash
printf 'reloaded\n'
EOF
chmod +x "$TEST_ROOT/reloaded-admin.sh"

cat > "$TEST_ROOT/bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$EVENTS"
if [[ "$*" == 'status --porcelain --untracked-files=normal' && "${DIRTY_GIT:-0}" == 1 ]]; then
  printf ' M scripts/cs2-admin.sh\n'
fi
[[ "$*" == 'pull --ff-only' || "$*" == 'status --porcelain --untracked-files=normal' ]]
EOF
cat > "$TEST_ROOT/bin/sudo" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -v ]] && exit 0
printf 'sudo %s\n' "$*" >> "$EVENTS"
if [[ "${FAIL_ROOT_INSTALL:-0}" == 1 && "${1:-}" == install && "$*" == *cs2-os-maintenance.sh* ]]; then
  exit 1
fi
"$@"
EOF
cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$EVENTS"
[[ "$*" == '--user daemon-reload' || "$*" == daemon-reload ]]
EOF
cat > "$TEST_ROOT/bin/flock" <<'EOF'
#!/usr/bin/env bash
[[ "${BUSY_LOCK:-0}" != 1 ]]
EOF
chmod +x "$TEST_ROOT/bin/"*

user_scripts=(cs2-workshop.py cs2-config.sh cs2-rcon.py cs2-buildid.py cs2-health.sh \
  cs2-safe-update.sh cs2-daily-home.sh update-cs2.sh start.sh cs2-admin.sh)
user_units=(cs2-ds.service cs2-update.service cs2-update.timer cs2-checkupdate.service \
  cs2-checkupdate.timer cs2-daily-home.service cs2-daily-home.timer)
root_units=(cs2-os-maintenance@.service cs2-os-maintenance@.timer)
for file in "${user_scripts[@]}"; do printf 'old %s\n' "$file" > "$TEST_ROOT/game/$file"; done
for file in "${user_units[@]}"; do printf 'old %s\n' "$file" > "$TEST_ROOT/home/.config/systemd/user/$file"; done
printf 'old root script\n' > "$TEST_ROOT/root/sbin/cs2-os-maintenance.sh"
for file in "${root_units[@]}"; do printf 'old %s\n' "$file" > "$TEST_ROOT/root/units/$file"; done

export TEST_ROOT EVENTS="$TEST_ROOT/events" CS2_HOME="$TEST_ROOT/home" CS2_DIR="$TEST_ROOT/game"
export TOOLKIT_REPO="$REPO" TOOLKIT_SCRIPT="$TEST_ROOT/reloaded-admin.sh"
export TOOLKIT_ROOT_SCRIPT_DIR="$TEST_ROOT/root/sbin" TOOLKIT_ROOT_UNIT_DIR="$TEST_ROOT/root/units"
export PATH="$TEST_ROOT/bin:$PATH"
ADMIN="$REPO/scripts/cs2-admin.sh"

FAIL_ROOT_INSTALL=1 "$ADMIN" update-toolkit > "$TEST_ROOT/failure.out" 2>&1 && {
  cat "$TEST_ROOT/failure.out"
  cat "$EVENTS"
  echo 'FAIL root deployment error was ignored'; exit 1;
}
for file in "${user_scripts[@]}"; do [[ "$(cat "$TEST_ROOT/game/$file")" == "old $file" ]]; done
for file in "${user_units[@]}"; do [[ "$(cat "$TEST_ROOT/home/.config/systemd/user/$file")" == "old $file" ]]; done
[[ "$(cat "$TEST_ROOT/root/sbin/cs2-os-maintenance.sh")" == 'old root script' ]]
for file in "${root_units[@]}"; do [[ "$(cat "$TEST_ROOT/root/units/$file")" == "old $file" ]]; done
[[ -z "$(find "$TEST_ROOT" -name '*.toolkit-update-*' -print -quit)" ]]
cmp -s "$TEST_ROOT/game/.update.env" "$TEST_ROOT/env.before"

: > "$EVENTS"
"$ADMIN" update-toolkit > "$TEST_ROOT/success.out" 2>&1
grep -Fxq reloaded "$TEST_ROOT/success.out"
for file in "${user_scripts[@]}"; do
  if [[ "$file" == cs2-admin.sh ]]; then
    cmp -s "$TEST_ROOT/game/$file" "$TEST_ROOT/reloaded-admin.sh"
  else
    cmp -s "$TEST_ROOT/game/$file" "$REPO/scripts/$file"
  fi
done
for file in "${user_units[@]}"; do cmp -s "$TEST_ROOT/home/.config/systemd/user/$file" "$REPO/systemd/$file"; done
cmp -s "$TEST_ROOT/root/sbin/cs2-os-maintenance.sh" "$REPO/scripts/cs2-os-maintenance.sh"
for file in "${root_units[@]}"; do cmp -s "$TEST_ROOT/root/units/$file" "$REPO/systemd/$file"; done
cmp -s "$TEST_ROOT/game/.update.env" "$TEST_ROOT/env.before"
grep -Fxq 'git pull --ff-only' "$EVENTS"
grep -Fxq 'git status --porcelain --untracked-files=normal' "$EVENTS"
grep -Fxq 'systemctl --user daemon-reload' "$EVENTS"
grep -Fxq 'sudo systemctl daemon-reload' "$EVENTS"
if grep -Fq restart "$EVENTS"; then echo 'FAIL game service was restarted'; exit 1; fi

: > "$EVENTS"
BUSY_LOCK=1 "$ADMIN" update-toolkit > "$TEST_ROOT/busy.out" 2>&1 && {
  echo 'FAIL busy update lock was ignored'; exit 1;
}
if grep -Fq systemctl "$EVENTS"; then echo 'FAIL busy deploy reloaded units'; exit 1; fi
cmp -s "$TEST_ROOT/game/.update.env" "$TEST_ROOT/env.before"

: > "$EVENTS"
DIRTY_GIT=1 "$ADMIN" update-toolkit > "$TEST_ROOT/dirty.out" 2>&1 && {
  echo 'FAIL dirty checkout was pulled'; exit 1;
}
grep -Fq 'local changes' "$TEST_ROOT/dirty.out"
if grep -Fq 'git pull --ff-only' "$EVENTS"; then echo 'FAIL dirty checkout was pulled'; exit 1; fi
echo 'PASS full_toolkit_deploy_rollback_and_busy_lock'
