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
[[ "$(grep -n '^bot_kick$' "$EVENTS" | head -n1 | cut -d: -f1)" -lt "$(grep -n '^exec cs2_toolkit.cfg$' "$EVENTS" | head -n1 | cut -d: -f1)" ]]

"$ADMIN" bot-off > "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '0 3 5' ]]
[[ "$(cat "$TEST_ROOT/bot_quota")" == 0 ]]
[[ "$(cat "$TEST_ROOT/active")" == 0 ]]
"$ADMIN" bot-on > "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '5 3 5' ]]

: > "$EVENTS"
TERM=xterm "$ADMIN" ui <<< $'b3\n2\n\n0\ne\n' > "$TEST_ROOT/output" 2>&1
grep -Fq 'Bot Management' "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '7 3 7' ]]

if "$ADMIN" bots-add '2;quit' > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL unsafe count accepted'; exit 1
fi
if "$ADMIN" bot-difficulty 4 > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL invalid difficulty accepted'; exit 1
fi
[[ "$(cat "$TEST_ROOT/game/toolkit-config/bots.txt")" == '7 3 7' ]]

echo 'PASS bot_management_persistence_and_validation'
