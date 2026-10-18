#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/home/cs2-ds"
printf 'ID=ubuntu\n' > "$TEST_ROOT/os-release"

# Redirect only the three root-owned system paths into this disposable tree.
sed -e "s@\. /etc/os-release@. \"$TEST_ROOT/os-release\"@" \
    -e "s@state_dir=/var/lib/cs2-toolkit@state_dir=$TEST_ROOT/root-state@" \
    -e "s@/run/reboot-required@$TEST_ROOT/reboot-required@g" \
    "$REPO/scripts/cs2-os-maintenance.sh" > "$TEST_ROOT/maintenance.sh"

cat > "$TEST_ROOT/bin/id" <<'EOF'
#!/usr/bin/env bash
echo 0
EOF
cat > "$TEST_ROOT/bin/getent" <<'EOF'
#!/usr/bin/env bash
printf 'cs2server:x:1000:1000::%s:/bin/bash\n' "$TEST_ROOT/home"
EOF
cat > "$TEST_ROOT/bin/runuser" <<'EOF'
#!/usr/bin/env bash
shift 2
[[ "$1" == -- ]] && shift
"$@"
EOF
cat > "$TEST_ROOT/bin/date" <<'EOF'
#!/usr/bin/env bash
case "$1" in +%H) echo 06 ;; +%F) echo 2026-10-18 ;; esac
EOF
cat > "$TEST_ROOT/bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TEST_ROOT/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt %s\n' "$*" >> "$EVENTS"
EOF
cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$EVENTS"
EOF
cat > "$TEST_ROOT/home/cs2-ds/cs2-admin.sh" <<'EOF'
#!/usr/bin/env bash
printf 'players : %s humans, 0 bots (10 max)\n' "$(cat "$TEST_ROOT/humans")"
EOF
chmod +x "$TEST_ROOT/bin/"* "$TEST_ROOT/home/cs2-ds/cs2-admin.sh"
export TEST_ROOT EVENTS="$TEST_ROOT/events" PATH="$TEST_ROOT/bin:$PATH"

printf '1\n' > "$TEST_ROOT/humans"
bash "$TEST_ROOT/maintenance.sh" cs2server > "$TEST_ROOT/output"
[[ ! -e "$EVENTS" ]]

printf '0\n' > "$TEST_ROOT/humans"
bash "$TEST_ROOT/maintenance.sh" cs2server > "$TEST_ROOT/output"
[[ "$(grep -c '^apt ' "$EVENTS")" == 2 ]]
[[ "$(cat "$TEST_ROOT/root-state/os-cs2server-updated.txt")" == '2026-10-18' ]]

touch "$TEST_ROOT/reboot-required"
bash "$TEST_ROOT/maintenance.sh" cs2server > "$TEST_ROOT/output"
[[ "$(grep -c '^apt ' "$EVENTS")" == 2 ]]
grep -Fxq 'systemctl reboot' "$EVENTS"

printf '1\n' > "$TEST_ROOT/humans"
: > "$EVENTS"
bash "$TEST_ROOT/maintenance.sh" cs2server > "$TEST_ROOT/output"
[[ ! -s "$EVENTS" ]]
echo 'PASS player_safe_os_update_and_reboot'
