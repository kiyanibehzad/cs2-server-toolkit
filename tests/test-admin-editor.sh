#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/game/game/csgo/cfg"
printf 'RCON_PASS=test\n' > "$TEST_ROOT/game/.update.env"
cat > "$TEST_ROOT/bin/editor" <<'EOF'
#!/usr/bin/env bash
[[ "${EDITOR_FAIL:-0}" == 1 ]] && exit 1
printf '// edited\n' >> "$1"
EOF
cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$EVENTS"
case "$*" in
  '--user is-active --quiet cs2-ds') [[ "${SERVICE_STOPPED:-0}" != 1 ]] ;;
  '--user list-unit-files --type=service') printf 'cs2-ds.service\n' ;;
  '--user restart cs2-ds') ;;
  *) exit 1 ;;
esac
EOF
cat > "$TEST_ROOT/bin/rcon-client" <<'EOF'
#!/usr/bin/env bash
cmd="${!#}"
case "$cmd" in
  status)
    if [[ "${BAD_STATUS:-0}" == 1 ]]; then printf 'status unavailable\n';
    else printf 'players : %s humans, 0 bots (10 max)\n' "${HUMANS:-0}"; fi
    ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/"*
export CS2_DIR="$TEST_ROOT/game" EVENTS="$TEST_ROOT/events" EDITOR="$TEST_ROOT/bin/editor"
export RCON_CLIENT="$TEST_ROOT/bin/rcon-client" PATH="$TEST_ROOT/bin:$PATH"
ADMIN="$REPO/scripts/cs2-admin.sh"

run_editor() {
  : > "$EVENTS"
  TERM=xterm "$ADMIN" ui <<< $'S\n1\n0\n\ne\n' > "$TEST_ROOT/output" 2>&1
}

EDITOR_FAIL=1 run_editor
grep -Fq 'Editor failed; restart skipped' "$TEST_ROOT/output"
if grep -Fq -- '--user restart cs2-ds' "$EVENTS"; then echo 'FAIL restart after editor error'; exit 1; fi

HUMANS=2 run_editor
grep -Fq '2 player(s) online; restart skipped' "$TEST_ROOT/output"
if grep -Fq -- '--user restart cs2-ds' "$EVENTS"; then echo 'FAIL restart with players online'; exit 1; fi

BAD_STATUS=1 run_editor
grep -Fq 'Player count unavailable; restart skipped' "$TEST_ROOT/output"
if grep -Fq -- '--user restart cs2-ds' "$EVENTS"; then echo 'FAIL restart without player count'; exit 1; fi

SERVICE_STOPPED=1 run_editor
grep -Fq 'Service is stopped; the file will apply on its next start' "$TEST_ROOT/output"
if grep -Fq -- '--user restart cs2-ds' "$EVENTS"; then echo 'FAIL restart of stopped service'; exit 1; fi

run_editor
grep -Fq -- '--user restart cs2-ds' "$EVENTS"
grep -Fq 'Service restarted and RCON ready' "$TEST_ROOT/output"

custom_input=$'C\nSafe Test\n1\n\n\n0\n24\n'
for ((i=0; i<10; i++)); do custom_input+=$'\n'; done
custom_input+=$'n\n\ne\n'
printf '%s' "$custom_input" | TERM=xterm "$ADMIN" ui > "$TEST_ROOT/output" 2>&1
grep -Fq 'Enter a number from 1 to 128' "$TEST_ROOT/output"
grep -Fxq 'mp_maxrounds 24' "$TEST_ROOT/game/game/csgo/cfg/custom_modes/safe_test.cfg"
echo 'PASS cfg_editor_safe_restart'
