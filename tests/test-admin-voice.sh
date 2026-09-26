#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/game"
printf 'RCON_PASS=test\n' > "$TEST_ROOT/game/.update.env"

cat > "$TEST_ROOT/bin/mcrcon" <<'EOF'
#!/usr/bin/env bash
cmd="${!#}"
printf '%s\n' "$cmd" >> "$EVENTS"
case "$cmd" in
  *' '*)
    name="${cmd%% *}"; value="${cmd#* }"
    [[ "$(cat "$TEST_ROOT/fail_on" 2>/dev/null)" == "$cmd" ]] && exit 1
    printf '%s\n' "$value" > "$TEST_ROOT/$name"
    ;;
  *) [[ -f "$TEST_ROOT/$cmd" ]] && printf '%s = %s\n' "$cmd" "$(cat "$TEST_ROOT/$cmd")" ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/mcrcon"
export TEST_ROOT EVENTS="$TEST_ROOT/events" CS2_DIR="$TEST_ROOT/game" PATH="$TEST_ROOT/bin:$PATH"
ADMIN="$REPO/scripts/cs2-admin.sh"

names=(sv_full_alltalk sv_alltalk sv_deadtalk sv_talk_enemy_living sv_talk_enemy_dead sv_auto_full_alltalk_during_warmup_half_end)
values() {
  local name
  for name in "${names[@]}"; do cat "$TEST_ROOT/$name"; done
}
assert_values() {
  local expected="$1"
  [[ "$(values | paste -sd ' ' -)" == "$expected" ]] || {
    printf 'Expected: %s\nActual: %s\n' "$expected" "$(values | paste -sd ' ' -)" >&2
    exit 1
  }
}
for name in "${names[@]}"; do printf '0\n' > "$TEST_ROOT/$name"; done

"$ADMIN" voice-mode both-teams > "$TEST_ROOT/output"
assert_values '0 1 1 0 0 0'
"$ADMIN" voice-status > "$TEST_ROOT/output"
grep -Fq 'Current: Both teams' "$TEST_ROOT/output"

"$ADMIN" voice-mode dead-all > "$TEST_ROOT/output"
assert_values '0 0 0 0 1 0'
"$ADMIN" voice-mode team-dead > "$TEST_ROOT/output"
assert_values '0 0 1 0 0 0'
"$ADMIN" voice-mode team > "$TEST_ROOT/output"
assert_values '0 0 0 0 0 0'
"$ADMIN" voice-mode all > "$TEST_ROOT/output"
assert_values '1 1 1 0 0 0'

: > "$EVENTS"
TERM=xterm "$ADMIN" ui <<< $'v4\n0\ne\n' > "$TEST_ROOT/output" 2>&1
grep -Fq 'Live Voice' "$TEST_ROOT/output"
assert_values '0 1 1 0 0 0'

: > "$EVENTS"
if "$ADMIN" voice-mode 'both-teams;quit' > "$TEST_ROOT/output" 2>&1; then
  echo 'Invalid mode accepted' >&2; exit 1
fi
[[ ! -s "$EVENTS" ]]

"$ADMIN" voice-mode team > "$TEST_ROOT/output"
printf 'sv_alltalk 1\n' > "$TEST_ROOT/fail_on"
if "$ADMIN" voice-mode all > "$TEST_ROOT/output" 2>&1; then
  echo 'Failed RCON write accepted' >&2; exit 1
fi
assert_values '0 0 0 0 0 0'
[[ ! -e "$TEST_ROOT/game/toolkit-config/voice.txt" ]]

echo 'PASS live_voice_modes_and_rollback'
