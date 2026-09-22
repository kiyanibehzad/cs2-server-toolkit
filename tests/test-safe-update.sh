#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/game/steamapps"
printf 'HOST_IP=127.0.0.1\nPORT=27015\nRCON_PASS=test\n' > "$TEST_ROOT/game/.update.env"
printf '"buildid" "100"\n' > "$TEST_ROOT/game/steamapps/appmanifest_730.acf"

cat > "$TEST_ROOT/bin/steamcmd" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *' +app_info_print '* ]]; then
  printf '"buildid" "%s"\n' "${REMOTE_BUILD:-200}"
elif [[ " $* " == *' +app_update '* ]]; then
  printf 'update %s\n' "$*" >> "$EVENTS"
  [[ "${UPDATE_FAIL:-0}" == 0 ]]
fi
EOF
cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *' show '*) cat "$STATE_FILE" ;;
  *' stop '*) echo stop >> "$EVENTS"; [[ "${STOP_FAIL:-0}" == 0 ]] || exit 1; echo inactive > "$STATE_FILE" ;;
  *' start '*) echo start >> "$EVENTS"; echo active > "$STATE_FILE" ;;
  *) exit 2 ;;
esac
EOF
cat > "$TEST_ROOT/bin/mcrcon" <<'EOF'
#!/usr/bin/env bash
[[ "${RCON_FAIL:-0}" == 0 ]] || exit 1
printf 'players : %s humans, 0 bots\n' "${HUMANS:-0}"
EOF
cat > "$TEST_ROOT/bin/flock" <<'EOF'
#!/usr/bin/env bash
[[ "${LOCK_BUSY:-0}" == 0 ]]
EOF
cat > "$TEST_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_ROOT/bin/"*

export PATH="$TEST_ROOT/bin:$PATH" STEAMCMD="$TEST_ROOT/bin/steamcmd"
export CS2_DIR="$TEST_ROOT/game" EVENTS="$TEST_ROOT/events" STATE_FILE="$TEST_ROOT/state"

run_case() {
  local name="$1" expected_exit="$2" expected_events="$3" mode="$4"; shift 4
  printf 'active\n' > "$STATE_FILE"
  : > "$EVENTS"
  local actual=0
  env "$@" "$REPO/scripts/cs2-safe-update.sh" "$mode" > "$TEST_ROOT/output" 2>&1 || actual=$?
  [[ "$actual" == "$expected_exit" ]] || { echo "FAIL $name: exit $actual"; cat "$TEST_ROOT/output"; exit 1; }
  local events
  events="$(cut -d' ' -f1 "$EVENTS" | paste -sd, -)"
  [[ "$events" == "$expected_events" ]] || { echo "FAIL $name: events '$events'"; exit 1; }
  echo "PASS $name"
}

run_case current 0 '' --check REMOTE_BUILD=100
run_case occupied 0 '' --check HUMANS=2
run_case force_occupied 0 '' --force HUMANS=2
run_case rcon_unavailable 1 '' --check RCON_FAIL=1
run_case update_success 0 'stop,update,start' --check
grep -Fq "+force_install_dir $CS2_DIR" "$EVENTS"
run_case update_failure 1 'stop,update,update,update,start' --check UPDATE_FAIL=1
run_case stop_failure 1 'stop,start' --check STOP_FAIL=1
run_case locked 0 '' --check LOCK_BUSY=1

printf 'inactive\n' > "$STATE_FILE"
: > "$EVENTS"
"$REPO/scripts/cs2-safe-update.sh" --force > "$TEST_ROOT/output" 2>&1
[[ "$(cut -d' ' -f1 "$EVENTS" | paste -sd, -)" == update ]] || {
  echo 'FAIL stopped_server'; exit 1;
}
echo 'PASS stopped_server'
