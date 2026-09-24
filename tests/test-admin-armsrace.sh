#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/game/game/csgo/maps"
cp "$REPO/scripts/cs2-config.sh" "$TEST_ROOT/game/cs2-config.sh"
chmod +x "$TEST_ROOT/game/cs2-config.sh"
printf 'HOST_IP=127.0.0.1\nPORT=27015\nRCON_PASS=test\n' > "$TEST_ROOT/game/.update.env"
touch "$TEST_ROOT/game/game/csgo/maps/ar_pool_day.vpk"
touch "$TEST_ROOT/game/game/csgo/maps/ar_shoots.vpk"
touch "$TEST_ROOT/game/game/csgo/maps/rush_001.vpk"
touch "$TEST_ROOT/game/game/csgo/maps/de_dust2.vpk"

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
  *' '*)
    name="${cmd%% *}"; value="${cmd#* }"
    printf '%s\n' "$value" > "$TEST_ROOT/$name"
    ;;
  *)
    [[ -f "$TEST_ROOT/$cmd" ]] && printf '%s = %s\n' "$cmd" "$(cat "$TEST_ROOT/$cmd")"
    true
    ;;
esac
EOF
cat > "$TEST_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TEST_ROOT/bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_ROOT/bin/"*

export PATH="$TEST_ROOT/bin:$PATH" CS2_DIR="$TEST_ROOT/game" TEST_ROOT
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
grep -Fxq 'sv_game_mode_flags 0' "$EVENTS"
grep -Fxq 'sv_skirmish_id 0' "$EVENTS"
grep -Fxq 'mp_respawn_on_death_t 1' "$EVENTS"
grep -Fxq 'mp_respawn_on_death_ct 1' "$EVENTS"
grep -Fxq 'exec cs2_toolkit.cfg' "$EVENTS"
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
if grep -Fxq 'mp_restartgame 1' "$EVENTS" || grep -Fxq 'say Game mode switched to: armsrace' "$EVENTS"; then
  echo 'FAIL failed_change: applied rules after map change failed'; exit 1
fi

unset CHANGE_FAIL
: > "$EVENTS"
"$REPO/scripts/cs2-admin.sh" rush-map rush_001 > "$TEST_ROOT/output" 2>&1
grep -Fxq 'game_type 0' "$EVENTS"
grep -Fxq 'game_mode 6' "$EVENTS"
grep -Fxq 'sv_skirmish_id 0' "$EVENTS"
grep -Fxq 'changelevel rush_001' "$EVENTS"
grep -Fxq 'bot_quota_mode fill' "$EVENTS"
grep -Fxq 'bot_quota 2' "$EVENTS"
if grep -Fxq 'bot_kick' "$EVENTS"; then
  echo 'FAIL rush_map_and_preset: kicked Rush fill bots'; exit 1
fi
[[ "$(grep -n '^game_mode 6$' "$EVENTS" | head -n1 | cut -d: -f1)" -lt "$(grep -n '^changelevel rush_001$' "$EVENTS" | head -n1 | cut -d: -f1)" ]]
echo 'PASS rush_map_and_preset'

: > "$EVENTS"
"$REPO/scripts/cs2-admin.sh" mode rush > "$TEST_ROOT/output" 2>&1
grep -Fxq 'changelevel rush_001' "$EVENTS"
echo 'PASS rush_mode_selects_its_map'

: > "$EVENTS"
if "$REPO/scripts/cs2-admin.sh" rush-map 'rush_001;quit' > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL unsafe Rush map accepted'; exit 1
fi
[[ ! -s "$EVENTS" ]]

rm "$TEST_ROOT/game/game/csgo/maps/rush_001.vpk"
: > "$EVENTS"
if "$REPO/scripts/cs2-admin.sh" rush-map rush_001 > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL missing Rush map accepted'; exit 1
fi
[[ ! -s "$EVENTS" ]]
echo 'PASS rush_invalid_or_missing_map'

printf 'de_dust2\n' > "$MAP_STATE"
touch "$TEST_ROOT/game/game/csgo/maps/rush_001.vpk"
"$REPO/scripts/cs2-admin.sh" mode rush rush_001 > "$TEST_ROOT/output" 2>&1
"$REPO/scripts/cs2-admin.sh" mode comp_mr12 de_dust2 > "$TEST_ROOT/output" 2>&1
[[ "$(cat "$MAP_STATE")" == de_dust2 ]]
[[ "$(cat "$TEST_ROOT/game_mode")" == 1 ]]
echo 'PASS rush_to_competitive_with_map'

"$REPO/scripts/cs2-admin.sh" mode retakes > "$TEST_ROOT/output" 2>&1
[[ "$(cat "$TEST_ROOT/sv_skirmish_id")" == 12 ]]
"$REPO/scripts/cs2-admin.sh" mode comp_mr12 > "$TEST_ROOT/output" 2>&1
[[ "$(cat "$TEST_ROOT/sv_skirmish_id")" == 0 ]]
[[ "$(cat "$TEST_ROOT/mp_overtime_enable")" == 1 ]]
[[ "$(cat "$TEST_ROOT/mp_overtime_maxrounds")" == 6 ]]
[[ "$(cat "$TEST_ROOT/bot_quota")" == 0 ]]
echo 'PASS retakes_to_competitive'

"$REPO/scripts/cs2-admin.sh" weapons-set 'AWP, Negev, AWP' > "$TEST_ROOT/output" 2>&1
[[ "$(cat "$TEST_ROOT/game/toolkit-config/blocked-weapons.txt")" == weapon_awp,weapon_negev ]]
[[ "$(cat "$TEST_ROOT/mp_items_prohibited")" == '"9,28"' ]]
"$REPO/scripts/cs2-admin.sh" weapons-clear > "$TEST_ROOT/output" 2>&1
[[ -z "$(cat "$TEST_ROOT/game/toolkit-config/blocked-weapons.txt")" ]]
[[ "$(cat "$TEST_ROOT/mp_items_prohibited")" == '""' ]]
echo 'PASS weapon_menu_persistence_and_clear'
