#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'if [[ "${KEEP_TEST_ROOT:-0}" == 1 ]]; then echo "TEST_ROOT=$TEST_ROOT"; else rm -rf "$TEST_ROOT"; fi' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/game/toolkit-config" "$TEST_ROOT/game/game/csgo/maps"
cp "$REPO/scripts/cs2-workshop.py" "$TEST_ROOT/game/cs2-workshop.py"
cp "$REPO/scripts/cs2-config.sh" "$TEST_ROOT/game/cs2-config.sh"
chmod +x "$TEST_ROOT/game/cs2-workshop.py" "$TEST_ROOT/game/cs2-config.sh"
printf 'HOST_IP=127.0.0.1\nPORT=27015\nRCON_PASS=test\n' > "$TEST_ROOT/game/.update.env"
printf 'de_dust2\n' > "$TEST_ROOT/map"
touch "$TEST_ROOT/game/game/csgo/maps/de_dust2.vpk"
printf '%s\n' '{"collection_id":"","maps":[],"manual_maps":[{"id":"111","title":"awp_india"}],"profiles":{"111":"awp"}}' > "$TEST_ROOT/game/toolkit-config/workshop.json"

cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ " $* " == *' is-active '* ]]
EOF
cat > "$TEST_ROOT/bin/mcrcon" <<'EOF'
#!/usr/bin/env bash
cmd="${!#}"
printf '%s\n' "$cmd" >> "$EVENTS"
if [[ "${REJECT_WORKSHOP_BUY:-0}" == 1 && "$cmd" == 'mp_buy_anywhere 0' ]]; then
  echo "Unknown command 'mp_buy_anywhere'!"
  exit 0
fi
case "$cmd" in
  status) printf 'SV:  [1: %s | server]\n' "$(cat "$TEST_ROOT/map")" ;;
  host_map) printf 'host_map : %s\n' "$(cat "$TEST_ROOT/map")" ;;
  host_workshop_map\ 111) printf 'awp_india\n' > "$TEST_ROOT/map" ;;
  changelevel\ *) printf '%s\n' "${cmd#changelevel }" > "$TEST_ROOT/map" ;;
  *' '*) printf '%s\n' "${cmd#* }" > "$TEST_ROOT/${cmd%% *}" ;;
  *) [[ -f "$TEST_ROOT/$cmd" ]] && printf '%s = %s\n' "$cmd" "$(cat "$TEST_ROOT/$cmd")"; true ;;
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
export PATH="$TEST_ROOT/bin:$PATH" CS2_DIR="$TEST_ROOT/game" TEST_ROOT EVENTS="$TEST_ROOT/events"
: > "$EVENTS"

if "$REPO/scripts/cs2-admin.sh" workshop-play '111;quit' > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL: unsafe Workshop ID accepted'; exit 1
fi
[[ ! -s "$EVENTS" ]]
if "$REPO/scripts/cs2-admin.sh" workshop-play 222 > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL: map outside collection accepted'; exit 1
fi
[[ ! -s "$EVENTS" ]]

"$REPO/scripts/cs2-admin.sh" workshop-play 111 > "$TEST_ROOT/output" 2>&1
grep -Fxq 'host_workshop_map 111' "$EVENTS"
grep -Fxq 'mp_t_default_primary weapon_awp' "$EVENTS"
grep -Fxq 'mp_ct_default_primary weapon_awp' "$EVENTS"
grep -Fxq 'mp_buytime 0' "$EVENTS"
[[ "$(cat "$TEST_ROOT/game/toolkit-config/workshop-active.txt")" == '111 awp_india' ]]

: > "$EVENTS"
"$REPO/scripts/cs2-admin.sh" workshop-play 111 scout > "$TEST_ROOT/output" 2>&1
! grep -Fq 'host_workshop_map' "$EVENTS"
grep -Fxq 'mp_t_default_primary weapon_ssg08' "$EVENTS"

: > "$EVENTS"
"$REPO/scripts/cs2-admin.sh" default > "$TEST_ROOT/output" 2>&1
grep -Fxq 'changelevel de_dust2' "$EVENTS"
grep -Fxq 'mp_t_default_primary ""' "$EVENTS"
grep -Fxq 'mp_buytime 20' "$EVENTS"
[[ ! -f "$TEST_ROOT/game/toolkit-config/workshop-active.txt" ]]

: > "$EVENTS"
if REJECT_WORKSHOP_BUY=1 "$REPO/scripts/cs2-admin.sh" workshop-play 111 > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL: partial Workshop preset accepted'; exit 1
fi
grep -Fxq 'changelevel de_dust2' "$EVENTS"
[[ "$(cat "$TEST_ROOT/map")" == de_dust2 ]]
[[ ! -f "$TEST_ROOT/game/toolkit-config/workshop-active.txt" ]]
echo 'PASS workshop_map_profile_and_home'
