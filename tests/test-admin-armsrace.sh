#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/game/game/csgo/maps"
printf 'HOST_IP=127.0.0.1\nPORT=27015\nRCON_PASS=test\n' > "$TEST_ROOT/game/.update.env"
touch "$TEST_ROOT/game/game/csgo/maps/ar_pool_day.vpk"
touch "$TEST_ROOT/game/game/csgo/maps/ar_shoots.vpk"

cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ " $* " == *' is-active '* ]]
EOF
cat > "$TEST_ROOT/bin/mcrcon" <<'EOF'
#!/usr/bin/env bash
cmd="${!#}"
printf '%s\n' "$cmd" >> "$EVENTS"
case "$cmd" in
  status) printf 'SV:  [1: %s | server]\n' "$(cat "$MAP_STATE")" ;;
  host_map) printf 'host_map : %s\n' "$(cat "$MAP_STATE")" ;;
  changelevel\ *)
    [[ "${CHANGE_FAIL:-0}" == 1 ]] || printf '%s\n' "${cmd#changelevel }" > "$MAP_STATE"
    ;;
esac
EOF
cat > "$TEST_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_ROOT/bin/"*

export PATH="$TEST_ROOT/bin:$PATH" CS2_DIR="$TEST_ROOT/game"
export EVENTS="$TEST_ROOT/events" MAP_STATE="$TEST_ROOT/map-state"

run_case() {
  local name="$1" expected="$2"; shift 2
  printf 'de_dust2\n' > "$MAP_STATE"
  : > "$EVENTS"
  local actual=0
  "$REPO/scripts/cs2-admin.sh" armsrace-map "$@" > "$TEST_ROOT/output" 2>&1 || actual=$?
  [[ "$actual" == "$expected" ]] || { echo "FAIL $name: exit $actual"; cat "$TEST_ROOT/output"; exit 1; }
  echo "PASS $name"
}

run_case pool_day 0 ar_pool_day
grep -Fxq 'game_type 1' "$EVENTS"
grep -Fxq 'game_mode 0' "$EVENTS"
grep -Fxq 'exec gamemode_armsrace.cfg' "$EVENTS"
grep -Fxq 'exec gamemode_armsrace_server.cfg' "$EVENTS"
grep -Fxq 'changelevel ar_pool_day' "$EVENTS"
[[ "$(cat "$MAP_STATE")" == ar_pool_day ]]
[[ "$(grep -n '^game_mode 0$' "$EVENTS" | head -n1 | cut -d: -f1)" -lt "$(grep -n '^changelevel ar_pool_day$' "$EVENTS" | head -n1 | cut -d: -f1)" ]]

run_case shoots 0 ar_shoots
grep -Fxq 'changelevel ar_shoots' "$EVENTS"

run_case missing_map 1 ar_baggage
[[ ! -s "$EVENTS" ]] || { echo 'FAIL missing_map: sent RCON commands'; exit 1; }

run_case unknown_map 1 'ar_pool_day;quit'
[[ ! -s "$EVENTS" ]] || { echo 'FAIL unknown_map: sent RCON commands'; exit 1; }

export CHANGE_FAIL=1
run_case failed_change 1 ar_pool_day
grep -Fxq 'changelevel ar_pool_day' "$EVENTS"
! grep -Fxq 'mp_restartgame 1' "$EVENTS"
! grep -Fxq 'say Game mode switched to: armsrace' "$EVENTS"
