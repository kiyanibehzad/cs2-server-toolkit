#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/game"
printf 'HOST_IP=127.0.0.1\nPORT=27015\nRCON_PASS=test\n' > "$TEST_ROOT/game/.update.env"

cat > "$TEST_ROOT/bin/date" <<'EOF'
#!/usr/bin/env bash
case "$1" in +%H) echo 06 ;; +%F) echo 2026-10-18 ;; esac
EOF
cat > "$TEST_ROOT/bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  is-active) exit 0 ;;
  restart|start) printf '%s\n' "$2" >> "$EVENTS" ;;
esac
EOF
cat > "$TEST_ROOT/game/cs2-rcon.py" <<'EOF'
#!/usr/bin/env bash
[[ -f "$TEST_ROOT/status-fail" ]] && exit 1
printf 'players : %s humans, 0 bots (10 max)\n' "$(cat "$TEST_ROOT/humans")"
EOF
cat > "$TEST_ROOT/game/cs2-admin.sh" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == rcon ]] && exit 0
printf '%s\n' "$1" >> "$EVENTS"
EOF
chmod +x "$TEST_ROOT/bin/"* "$TEST_ROOT/game/cs2-rcon.py" "$TEST_ROOT/game/cs2-admin.sh"
export TEST_ROOT EVENTS="$TEST_ROOT/events" CS2_DIR="$TEST_ROOT/game" PATH="$TEST_ROOT/bin:$PATH"

printf '1\n' > "$TEST_ROOT/humans"
bash "$REPO/scripts/cs2-daily-home.sh" > "$TEST_ROOT/output"
[[ ! -e "$EVENTS" ]]
[[ ! -e "$TEST_ROOT/game/toolkit-config/daily-home-done.txt" ]]

printf '0\n' > "$TEST_ROOT/humans"
touch "$TEST_ROOT/status-fail"
bash "$REPO/scripts/cs2-daily-home.sh" > "$TEST_ROOT/output" 2>&1
[[ ! -e "$EVENTS" ]]
rm "$TEST_ROOT/status-fail"

bash "$REPO/scripts/cs2-daily-home.sh" > "$TEST_ROOT/output"
[[ "$(cat "$EVENTS")" == $'restart\ndefault' ]]
[[ "$(cat "$TEST_ROOT/game/toolkit-config/daily-home-done.txt")" == '2026-10-18' ]]
bash "$REPO/scripts/cs2-daily-home.sh" > "$TEST_ROOT/output"
[[ "$(cat "$EVENTS")" == $'restart\ndefault' ]]
echo 'PASS empty_player_daily_home_once'
