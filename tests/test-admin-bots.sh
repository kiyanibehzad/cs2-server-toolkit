#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/game/game/csgo/cfg"
cp "$REPO/scripts/cs2-config.sh" "$TEST_ROOT/game/cs2-config.sh"
chmod +x "$TEST_ROOT/game/cs2-config.sh"
printf 'RCON_PASS=test\n' > "$TEST_ROOT/game/.update.env"
printf '2\n' > "$TEST_ROOT/bot_quota"
printf 'fill\n' > "$TEST_ROOT/bot_quota_mode"
printf '2\n' > "$TEST_ROOT/bot_difficulty"
printf '2\n' > "$TEST_ROOT/active"

cat > "$TEST_ROOT/bin/mcrcon" <<'EOF'
#!/usr/bin/env bash
cmd="${!#}"
printf '%s\n' "$cmd" >> "$EVENTS"
if [[ -f "$TEST_ROOT/fail_on" && "$cmd" == "$(cat "$TEST_ROOT/fail_on")" ]]; then
  rm -f "$TEST_ROOT/fail_on"
  exit 1
fi
case "$cmd" in
  status) printf 'players : 1 humans, %s bots (10 max)\n' "$(cat "$TEST_ROOT/active")" ;;
  'exec cs2_toolkit.cfg')
    while read -r name value; do
      case "$name" in bot_*|sv_auto_adjust_bot_difficulty) printf '%s\n' "$value" > "$TEST_ROOT/$name" ;; esac
    done < "$TEST_ROOT/game/game/csgo/cfg/cs2_toolkit.cfg"
    [[ "$(cat "$TEST_ROOT/bot_quota_mode")" == normal ]] && cp "$TEST_ROOT/bot_quota" "$TEST_ROOT/active"
    ;;
  bot_kick) printf '0\n' > "$TEST_ROOT/active" ;;
  *' '*)
    name="${cmd%% *}"; value="${cmd#* }"
    printf '%s\n' "$value" > "$TEST_ROOT/$name"
    ;;
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

"$ADMIN" bots-add 3 > "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '5 2 5' ]]
grep -Fxq 'bot_quota 5' "$TEST_ROOT/game/game/csgo/cfg/cs2_toolkit.cfg"
[[ "$(cat "$TEST_ROOT/bot_quota")" == 5 ]]

: > "$EVENTS"
"$ADMIN" bot-difficulty 3 > "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '5 3 5' ]]
[[ "$(cat "$TEST_ROOT/bot_difficulty")" == 3 ]]
[[ "$(cat "$TEST_ROOT/sv_auto_adjust_bot_difficulty")" == 0 ]]
if grep -Fxq 'bot_kick' "$EVENTS"; then echo 'FAIL difficulty change kicked bots'; exit 1; fi
if grep -Fxq 'exec cs2_toolkit.cfg' "$EVENTS"; then echo 'FAIL difficulty change reset bot mode'; exit 1; fi

"$ADMIN" bot-off > "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '0 3 5' ]]
[[ "$(cat "$TEST_ROOT/bot_quota")" == 0 ]]
[[ "$(cat "$TEST_ROOT/active")" == 0 ]]
"$ADMIN" bot-on > "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '5 3 5' ]]

: > "$EVENTS"
TERM=xterm "$ADMIN" ui <<< $'b3\n2\n\ne\n' > "$TEST_ROOT/output" 2>&1
grep -Fq '[Bots: type code + Enter]' "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '7 3 7' ]]

TERM=xterm "$ADMIN" ui <<< $'m\n0\ne\n' > "$TEST_ROOT/output" 2>&1
grep -Fq 'Maintenance and Server Tools' "$TEST_ROOT/output"

: > "$EVENTS"
TERM=xterm "$ADMIN" ui <<< $'b2x\n\ne\n' > "$TEST_ROOT/output" 2>&1
grep -Fq 'Unknown bot shortcut: b2x' "$TEST_ROOT/output"
[[ ! -s "$EVENTS" ]]
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '7 3 7' ]]

printf 'b2' | TERM=xterm "$ADMIN" ui > "$TEST_ROOT/output" 2>&1
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '7 3 7' ]]

grep -Eq 'CS2 Quick Admin v[0-9]+\.[0-9]+\.[0-9]+' "$TEST_ROOT/output"
grep -Fq '[Warmup]' "$TEST_ROOT/output"

if "$ADMIN" bots-add '2;quit' > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL unsafe count accepted'; exit 1
fi
if "$ADMIN" bot-difficulty 4 > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL invalid difficulty accepted'; exit 1
fi
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '7 3 7' ]]

printf 'exec cs2_toolkit.cfg\n' > "$TEST_ROOT/fail_on"
if "$ADMIN" bot-quota 9 > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL failed live bot change was reported as successful'; exit 1
fi
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '7 3 7' ]]
grep -Fxq 'bot_quota 7' "$TEST_ROOT/game/game/csgo/cfg/cs2_toolkit.cfg"
[[ "$(cat "$TEST_ROOT/bot_quota")" == 7 ]]

printf 'bot_difficulty 1\n' > "$TEST_ROOT/fail_on"
if "$ADMIN" bot-difficulty 1 > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL failed live bot difficulty was reported as successful'; exit 1
fi
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '7 3 7' ]]
[[ "$(cat "$TEST_ROOT/bot_difficulty")" == 3 ]]

rm -f "$TEST_ROOT/game/toolkit-config/bots.txt"
"$TEST_ROOT/game/cs2-config.sh" sync
printf 'fill\n' > "$TEST_ROOT/bot_quota_mode"
"$ADMIN" bot-difficulty 1 > "$TEST_ROOT/output"
[[ ! -e "$TEST_ROOT/game/toolkit-config/bots.txt" ]]
[[ "$(cat "$TEST_ROOT/bot_quota_mode")" == fill ]]
if grep -q '^bot_quota_mode ' "$TEST_ROOT/game/game/csgo/cfg/cs2_toolkit.cfg"; then
  echo 'FAIL difficulty-only setting changed future bot mode'; exit 1
fi
grep -Fq 'for this map' "$TEST_ROOT/output"

echo 'PASS bot_management_persistence_and_validation'
