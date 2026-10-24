#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/game"
printf 'HOST_IP=203.0.113.20\nRCON_HOST=127.0.0.1\nRCON_PASS=test\n' > "$TEST_ROOT/game/.update.env"
sid=76561197991429996
printf '%s\n' "$sid" > "$TEST_ROOT/bans"
cat > "$TEST_ROOT/bin/rcon-client" <<'EOF'
#!/usr/bin/env bash
cmd="${!#}"
printf '%s %s\n' "$2" "$cmd" >> "$EVENTS"
case "$cmd" in
  listid) cat "$TEST_ROOT/bans" ;;
  removeid\ *)
    [[ "${REMOVE_FAIL:-0}" == 1 ]] && exit 1
    if [[ "${REMOVE_NOOP:-0}" != 1 ]]; then
      grep -Fxv -- "${cmd#removeid }" "$TEST_ROOT/bans" > "$TEST_ROOT/remaining" || true
      mv "$TEST_ROOT/remaining" "$TEST_ROOT/bans"
    fi
    ;;
  writeid) [[ "${WRITE_FAIL:-0}" != 1 ]] ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/rcon-client"
export TEST_ROOT EVENTS="$TEST_ROOT/events" CS2_DIR="$TEST_ROOT/game"
export RCON_CLIENT="$TEST_ROOT/bin/rcon-client" PATH="$TEST_ROOT/bin:$PATH"
ADMIN="$REPO/scripts/cs2-admin.sh"

REMOVE_FAIL=1 "$ADMIN" unban-select <<< 1 > "$TEST_ROOT/output" 2>&1 && {
  echo 'FAIL removeid error was ignored'; exit 1;
}
grep -Fq 'Could not remove the ban' "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/bans")" == "$sid" ]]

WRITE_FAIL=1 "$ADMIN" unban-select <<< 1 > "$TEST_ROOT/output" 2>&1 && {
  echo 'FAIL writeid error was ignored'; exit 1;
}
grep -Fq 'could not save the ban list' "$TEST_ROOT/output"

printf '%s\n' "$sid" > "$TEST_ROOT/bans"
REMOVE_NOOP=1 "$ADMIN" unban-select <<< 1 > "$TEST_ROOT/output" 2>&1 && {
  echo 'FAIL still-banned user was reported as removed'; exit 1;
}
grep -Fq 'ban is still present' "$TEST_ROOT/output"

"$ADMIN" unban-select <<< 1 > "$TEST_ROOT/output"
grep -Fq 'Ban removed and saved' "$TEST_ROOT/output"
[[ ! -s "$TEST_ROOT/bans" ]]
grep -Fq '127.0.0.1 removeid' "$EVENTS"

printf 'STEAM_1:0:123\nSTEAM_1:0:1234\n' > "$TEST_ROOT/bans"
"$ADMIN" unban-select <<< 1 > "$TEST_ROOT/output"
grep -Fq 'Ban removed and saved' "$TEST_ROOT/output"
[[ "$(cat "$TEST_ROOT/bans")" == 'STEAM_1:0:1234' ]]

TERM=xterm "$ADMIN" ui <<< e > "$TEST_ROOT/output" 2>&1
grep -Fq 'connect 203.0.113.20:27015' "$TEST_ROOT/output"
if grep -Fq 'connect 127.0.0.1:27015' "$TEST_ROOT/output"; then
  echo 'FAIL private RCON host was shown as the join address'; exit 1
fi
cat > "$TEST_ROOT/bin/mcrcon" <<'EOF'
#!/usr/bin/env bash
touch "$TEST_ROOT/insecure-fallback-was-used"
EOF
chmod +x "$TEST_ROOT/bin/mcrcon"
if RCON_CLIENT="$TEST_ROOT/bin/missing-client" "$ADMIN" list-banned > "$TEST_ROOT/output" 2>&1; then
  echo 'FAIL missing safe RCON client was ignored'; exit 1
fi
[[ ! -e "$TEST_ROOT/insecure-fallback-was-used" ]]
echo 'PASS unban_confirmation_and_rcon_address'
