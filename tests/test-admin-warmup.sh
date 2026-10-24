#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/game/game/csgo/cfg"
cp "$REPO/scripts/cs2-config.sh" "$TEST_ROOT/game/cs2-config.sh"
chmod +x "$TEST_ROOT/game/cs2-config.sh"
printf 'RCON_PASS=test\n' > "$TEST_ROOT/game/.update.env"
printf '120\n' > "$TEST_ROOT/mp_warmuptime"
printf '15\n' > "$TEST_ROOT/mp_warmuptime_all_players_connected"

cat > "$TEST_ROOT/bin/mcrcon" <<'EOF'
#!/usr/bin/env bash
cmd="${!#}"
printf '%s\n' "$cmd" >> "$EVENTS"
case "$cmd" in
  *' '*) printf '%s\n' "${cmd#* }" > "$TEST_ROOT/${cmd%% *}" ;;
  *) [[ -f "$TEST_ROOT/$cmd" ]] && printf '%s = %s\n' "$cmd" "$(cat "$TEST_ROOT/$cmd")" ;;
esac
EOF
cat > "$TEST_ROOT/bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_ROOT/bin/"*
export TEST_ROOT EVENTS="$TEST_ROOT/events" CS2_DIR="$TEST_ROOT/game" PATH="$TEST_ROOT/bin:$PATH"
export RCON_CLIENT="$TEST_ROOT/bin/mcrcon"
ADMIN="$REPO/scripts/cs2-admin.sh"

"$ADMIN" warmup-set 45 > "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/game/toolkit-config/warmup.txt")" == '45 45' ]]
grep -Fxq 'mp_warmuptime 45' "$TEST_ROOT/game/game/csgo/cfg/cs2_toolkit.cfg"
grep -Fxq 'mp_warmuptime_all_players_connected 45' "$TEST_ROOT/game/game/csgo/cfg/cs2_toolkit.cfg"

"$ADMIN" warmup-set 0 > "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/game/toolkit-config/warmup.txt")" == '0 45' ]]
grep -Fxq mp_warmup_end "$EVENTS"
"$ADMIN" warmup-set 45 > "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/mp_warmuptime")" == 45 ]]

if "$ADMIN" warmup-set '45;quit' > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL unsafe duration accepted' >&2; exit 1
fi
[[ "$(cat "$TEST_ROOT/game/toolkit-config/warmup.txt")" == '45 45' ]]
echo 'PASS permanent_warmup_settings'
