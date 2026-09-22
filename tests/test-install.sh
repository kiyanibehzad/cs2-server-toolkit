#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/home/steamcmd"

cat > "$TEST_ROOT/bin/id" <<'EOF'
#!/usr/bin/env bash
case "$1" in -u) echo 1000 ;; -un) echo cs2server ;; esac
EOF
cat > "$TEST_ROOT/bin/getent" <<'EOF'
#!/usr/bin/env bash
printf 'cs2server:x:1000:1000::%s:/bin/bash\n' "$HOME"
EOF
cat > "$TEST_ROOT/bin/sudo" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TEST_ROOT/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TEST_ROOT/bin/mcrcon" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_ROOT/systemctl-calls"
EOF
cat > "$TEST_ROOT/home/steamcmd/steamcmd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_ROOT/steamcmd-calls"
previous=""
for arg in "$@"; do
  if [[ "$previous" == +force_install_dir ]]; then
    mkdir -p "$arg/game/bin/linuxsteamrt64"
    touch "$arg/game/bin/linuxsteamrt64/cs2"
    chmod +x "$arg/game/bin/linuxsteamrt64/cs2"
  fi
  previous="$arg"
done
EOF
chmod +x "$TEST_ROOT/bin/"* "$TEST_ROOT/home/steamcmd/steamcmd.sh"

export TEST_ROOT HOME="$TEST_ROOT/home" PATH="$TEST_ROOT/bin:$PATH"
export HOST_IP=127.0.0.1 PORT=27015 RCON_PASS='test-pass' SERVER_NAME='Test Server'
export SERVER_PASS='join-pass' GSLT='test-token'

printf 'old manual updater\n' > "$HOME/update-cs2.sh"
"$REPO/install.sh" < /dev/null > "$TEST_ROOT/output"
grep -Fq "+force_install_dir $HOME/cs2-ds" "$TEST_ROOT/steamcmd-calls"
[[ -L "$HOME/update-cs2.sh" ]]
grep -Fq 'old manual updater' "$HOME"/update-cs2.sh.legacy-*
[[ "$(ls -l "$HOME/cs2-ds/.update.env" | cut -c1-10)" == '-rw-------' ]]
[[ "$(ls -l "$HOME/cs2-ds/game/csgo/cfg/cs2server.cfg" | cut -c1-10)" == '-rw-------' ]]
grep -Fq 'ExecStart=%h/cs2-ds/cs2-safe-update.sh --check' "$HOME/.config/systemd/user/cs2-update.service"
cp "$HOME/cs2-ds/.update.env" "$TEST_ROOT/env-before"
cp "$HOME/cs2-ds/game/csgo/cfg/cs2server.cfg" "$TEST_ROOT/cfg-before"

export RCON_PASS='different-pass' SERVER_NAME='Changed Name'
"$REPO/install.sh" < /dev/null > "$TEST_ROOT/output"
cmp "$TEST_ROOT/env-before" "$HOME/cs2-ds/.update.env"
cmp "$TEST_ROOT/cfg-before" "$HOME/cs2-ds/game/csgo/cfg/cs2server.cfg"
[[ "$(wc -l < "$TEST_ROOT/steamcmd-calls")" -eq 1 ]]
echo 'PASS initial_install_and_safe_reinstall'

export CS2_HOME="$HOME" CS2_DIR="$HOME/cs2-ds"
printf '1\nnew-pass\n0\n' | "$HOME/cs2-ds/cs2-admin.sh" join-pass-menu > "$TEST_ROOT/admin-output"
grep -Fq 'SERVER_PASS=new-pass' "$HOME/cs2-ds/.update.env"
grep -Fq 'sv_password "new-pass"' "$HOME/cs2-ds/game/csgo/cfg/cs2server.cfg"
if grep -Fq 'new-pass' "$TEST_ROOT/admin-output"; then
  echo 'FAIL password exposed in admin output'
  exit 1
fi
echo 'PASS join_password_persistence'
