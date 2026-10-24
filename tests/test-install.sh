#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/home/steamcmd"
cat > "$TEST_ROOT/os-release" <<'EOF'
ID=ubuntu
VERSION_ID=26.04
EOF
cat > "$TEST_ROOT/os-release-bad" <<'EOF'
ID=ubuntu
VERSION_ID=26.10
EOF

cat > "$TEST_ROOT/bin/uname" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -m ]] && { echo x86_64; exit 0; }
exit 1
EOF
cat > "$TEST_ROOT/bin/df" <<'EOF'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/fake 200000000 10000000 %s 5%% /\n' "${TEST_FREE_KIB:-190000000}"
EOF
cat > "$TEST_ROOT/bin/ip" <<'EOF'
#!/usr/bin/env bash
printf '1: lo    inet 127.0.0.1/8 scope host lo\n2: eth0    inet 10.0.0.5/24 scope global eth0\n'
EOF

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
printf '%s\n' "$*" >> "$TEST_ROOT/sudo-calls"
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
cat > "$TEST_ROOT/bin/flock" <<'EOF'
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
if [[ "${STEAMCMD_FAIL_FIRST:-0}" == 1 && ! -e "$TEST_ROOT/steamcmd-failed-once" ]]; then
  touch "$TEST_ROOT/steamcmd-failed-once"
  exit 0
fi
previous=""
for arg in "$@"; do
  if [[ "$previous" == +force_install_dir ]]; then
    mkdir -p "$arg/game/bin/linuxsteamrt64"
    touch "$arg/game/bin/linuxsteamrt64/cs2"
    chmod +x "$arg/game/bin/linuxsteamrt64/cs2"
    mkdir -p "$arg/steamapps"
    printf '"AppState"\n{\n "buildid" "123456"\n}\n' > "$arg/steamapps/appmanifest_730.acf"
  fi
  previous="$arg"
done
EOF
chmod +x "$TEST_ROOT/bin/"* "$TEST_ROOT/home/steamcmd/steamcmd.sh"

export TEST_ROOT HOME="$TEST_ROOT/home" PATH="$TEST_ROOT/bin:$PATH"
export OS_RELEASE_FILE="$TEST_ROOT/os-release"
export HOST_IP=127.0.0.1 PORT=27015 RCON_PASS='test-pass' SERVER_NAME='Test Server'
export SERVER_PASS='join-pass' GSLT='test-token'

printf 'old manual updater\n' > "$HOME/update-cs2.sh"
"$REPO/install.sh" < /dev/null > "$TEST_ROOT/output"
grep -Fq "+force_install_dir $HOME/cs2-ds" "$TEST_ROOT/steamcmd-calls"
[[ -L "$HOME/update-cs2.sh" ]]
grep -Fq 'old manual updater' "$HOME"/update-cs2.sh.legacy-*
[[ "$(ls -l "$HOME/cs2-ds/.update.env" | cut -c1-10)" == '-rw-------' ]]
[[ "$(ls -l "$HOME/cs2-ds/game/csgo/cfg/cs2server.cfg" | cut -c1-10)" == '-rw-------' ]]
[[ -x "$HOME/cs2-ds/cs2-rcon.py" && -x "$HOME/cs2-ds/cs2-config.sh" && -x "$HOME/cs2-ds/cs2-buildid.py" ]]
[[ -x "$HOME/cs2-ds/cs2-daily-home.sh" ]]
[[ -x "$HOME/cs2-ds/cs2-workshop.py" ]]
! grep -Fq 'sv_setsteamaccount' "$HOME/cs2-ds/game/csgo/cfg/cs2server.cfg"
grep -Fxq 'exec cs2_toolkit.cfg' "$HOME/cs2-ds/game/csgo/cfg/gamemode_competitive_server.cfg"
grep -Fq 'ExecStart=%h/cs2-ds/cs2-safe-update.sh --check' "$HOME/.config/systemd/user/cs2-update.service"
grep -Fq 'enable --now cs2-daily-home.timer' "$TEST_ROOT/systemctl-calls"
grep -Fq 'enable --now cs2-os-maintenance@cs2server.timer' "$TEST_ROOT/sudo-calls"
grep -Fq 'disable --now apt-daily.timer apt-daily-upgrade.timer' "$TEST_ROOT/sudo-calls"
grep -Fq '/var/lib/cs2-toolkit' "$TEST_ROOT/sudo-calls"
grep -Fxq 'BIND_IP=127.0.0.1' "$HOME/cs2-ds/.update.env"
grep -Fxq 'RCON_HOST=127.0.0.1' "$HOME/cs2-ds/.update.env"
cp "$HOME/cs2-ds/.update.env" "$TEST_ROOT/env-before"
cp "$HOME/cs2-ds/game/csgo/cfg/cs2server.cfg" "$TEST_ROOT/cfg-before"

export RCON_PASS='different-pass' SERVER_NAME='Changed Name'
"$REPO/install.sh" < /dev/null > "$TEST_ROOT/output"
cmp "$TEST_ROOT/env-before" "$HOME/cs2-ds/.update.env"
cmp "$TEST_ROOT/cfg-before" "$HOME/cs2-ds/game/csgo/cfg/cs2server.cfg"
[[ "$(wc -l < "$TEST_ROOT/steamcmd-calls")" -eq 1 ]]
echo 'PASS initial_install_and_safe_reinstall'

# A public address behind NAT cannot be used as a local bind address. Fresh
# installs use an all-interface listener and local RCON; reinstall preserves it.
mkdir -p "$TEST_ROOT/nat-home/steamcmd"
cp "$TEST_ROOT/home/steamcmd/steamcmd.sh" "$TEST_ROOT/nat-home/steamcmd/steamcmd.sh"
HOME="$TEST_ROOT/nat-home" HOST_IP=203.0.113.45 "$REPO/install.sh" < /dev/null > "$TEST_ROOT/nat-output"
grep -Fxq 'HOST_IP=203.0.113.45' "$TEST_ROOT/nat-home/cs2-ds/.update.env"
grep -Fxq 'BIND_IP=0.0.0.0' "$TEST_ROOT/nat-home/cs2-ds/.update.env"
grep -Fxq 'RCON_HOST=127.0.0.1' "$TEST_ROOT/nat-home/cs2-ds/.update.env"
grep -Fq 'binding on all IPv4 interfaces' "$TEST_ROOT/nat-output"
echo 'PASS nat_bind_and_local_rcon'

mkdir -p "$TEST_ROOT/retry-home/steamcmd"
cp "$TEST_ROOT/home/steamcmd/steamcmd.sh" "$TEST_ROOT/retry-home/steamcmd/steamcmd.sh"
if HOME="$TEST_ROOT/retry-home" HOST_IP=203.0.113.45 BIND_IP=198.51.100.7 \
    "$REPO/install.sh" < /dev/null > "$TEST_ROOT/bad-bind-output" 2>&1; then
  echo 'FAIL non-local BIND_IP was accepted'
  exit 1
fi
grep -Fq 'not assigned to a local IPv4 interface' "$TEST_ROOT/bad-bind-output"
if HOME="$TEST_ROOT/retry-home" OS_RELEASE_FILE="$TEST_ROOT/os-release-bad" \
    "$REPO/install.sh" < /dev/null > "$TEST_ROOT/bad-os-output" 2>&1; then
  echo 'FAIL unsupported OS was accepted'
  exit 1
fi
grep -Fq 'Unsupported OS' "$TEST_ROOT/bad-os-output"
if HOME="$TEST_ROOT/retry-home" TEST_FREE_KIB=1000000 \
    "$REPO/install.sh" < /dev/null > "$TEST_ROOT/low-disk-output" 2>&1; then
  echo 'FAIL insufficient disk space was accepted'
  exit 1
fi
grep -Fq 'At least 60 GiB' "$TEST_ROOT/low-disk-output"
STEAMCMD_FAIL_FIRST=1 HOME="$TEST_ROOT/retry-home" HOST_IP=203.0.113.45 \
  BIND_IP=10.0.0.5 "$REPO/install.sh" < /dev/null > "$TEST_ROOT/retry-output" 2>&1
grep -Fq 'CS2 download did not pass validation (attempt 1/3)' "$TEST_ROOT/retry-output"
[[ -x "$TEST_ROOT/retry-home/cs2-ds/game/bin/linuxsteamrt64/cs2" ]]
[[ -s "$TEST_ROOT/retry-home/cs2-ds/steamapps/appmanifest_730.acf" ]]
grep -Fxq 'BIND_IP=10.0.0.5' "$TEST_ROOT/retry-home/cs2-ds/.update.env"
grep -Fxq 'RCON_HOST=10.0.0.5' "$TEST_ROOT/retry-home/cs2-ds/.update.env"
echo 'PASS installer_preflight_and_download_retry'

calls_before="$(wc -l < "$TEST_ROOT/steamcmd-calls")"
rm "$TEST_ROOT/retry-home/cs2-ds/steamapps/appmanifest_730.acf"
HOME="$TEST_ROOT/retry-home" "$REPO/install.sh" < /dev/null > "$TEST_ROOT/repair-output"
[[ "$(wc -l < "$TEST_ROOT/steamcmd-calls")" -eq $(( calls_before + 1 )) ]]
[[ -s "$TEST_ROOT/retry-home/cs2-ds/steamapps/appmanifest_730.acf" ]]
echo 'PASS incomplete_game_install_revalidated'

tar -czf "$TEST_ROOT/steamcmd-test.tar.gz" -C "$TEST_ROOT/home/steamcmd" steamcmd.sh
cat > "$TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
destination=""
while (( $# )); do
  if [[ "$1" == -o ]]; then destination="$2"; shift 2; else shift; fi
done
if [[ ! -e "$TEST_ROOT/bootstrap-failed-once" ]]; then
  touch "$TEST_ROOT/bootstrap-failed-once"
  exit 22
fi
cp "$TEST_ROOT/steamcmd-test.tar.gz" "$destination"
EOF
chmod +x "$TEST_ROOT/bin/curl"
mkdir -p "$TEST_ROOT/bootstrap-home"
HOME="$TEST_ROOT/bootstrap-home" "$REPO/install.sh" < /dev/null > "$TEST_ROOT/bootstrap-output" 2>&1
grep -Fq 'SteamCMD bootstrap failed (attempt 1/3)' "$TEST_ROOT/bootstrap-output"
[[ -x "$TEST_ROOT/bootstrap-home/steamcmd/steamcmd.sh" ]]
[[ -x "$TEST_ROOT/bootstrap-home/cs2-ds/game/bin/linuxsteamrt64/cs2" ]]
rm "$TEST_ROOT/bin/curl"
echo 'PASS steamcmd_bootstrap_retry'

export CS2_HOME="$HOME" CS2_DIR="$HOME/cs2-ds"
export RCON_CLIENT="$TEST_ROOT/bin/mcrcon"
printf '1\nnew-pass\n0\n' | "$HOME/cs2-ds/cs2-admin.sh" join-pass-menu > "$TEST_ROOT/admin-output"
grep -Fq 'SERVER_PASS=new-pass' "$HOME/cs2-ds/.update.env"
grep -Fq 'sv_password "new-pass"' "$HOME/cs2-ds/game/csgo/cfg/cs2server.cfg"
if grep -Fq 'new-pass' "$TEST_ROOT/admin-output"; then
  echo 'FAIL password exposed in admin output'
  exit 1
fi
echo 'PASS join_password_persistence'

printf 'sv_setsteamaccount "oldtoken"\n' >> "$HOME/cs2-ds/game/csgo/cfg/cs2server.cfg"
printf '1\ninvalid token\n1\nnewtoken123456\ny\n0\n' | "$HOME/cs2-ds/cs2-admin.sh" game-token-menu > "$TEST_ROOT/admin-output"
grep -Fxq 'GSLT=newtoken123456' "$HOME/cs2-ds/.update.env"
[[ "$(grep -c '^GSLT=' "$HOME/cs2-ds/.update.env")" -eq 1 ]]
[[ "$(ls -l "$HOME/cs2-ds/.update.env" | cut -c1-10)" == '-rw-------' ]]
! grep -Fq 'sv_setsteamaccount' "$HOME/cs2-ds/game/csgo/cfg/cs2server.cfg"
grep -Fq 'sv_setsteamaccount "oldtoken"' "$HOME"/cs2-ds/game/csgo/cfg/cs2server.cfg.before-gslt-change.*
if grep -Fq 'newtoken123456' "$TEST_ROOT/admin-output"; then
  echo 'FAIL token exposed in admin output'
  exit 1
fi
! grep -Fq -- '--user restart cs2-ds' "$TEST_ROOT/systemctl-calls"
echo 'PASS game_token_persistence'

TERM=xterm "$HOME/cs2-ds/cs2-admin.sh" ui <<< $'m\n0\ne\n' > "$TEST_ROOT/admin-output" 2>&1
grep -Fq '11) Set or replace game login token (GSLT)' "$TEST_ROOT/admin-output"
grep -Fq '12) Join password menu' "$TEST_ROOT/admin-output"
if grep -Eq '\[Access\]|J\) Join password menu' "$TEST_ROOT/admin-output"; then
  echo 'FAIL password shortcut still on main menu'
  exit 1
fi
echo 'PASS access_settings_in_tools'

cat > "$HOME/cs2-ds/game/bin/linuxsteamrt64/cs2" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_ROOT/launch-args"
EOF
chmod +x "$HOME/cs2-ds/game/bin/linuxsteamrt64/cs2"
"$HOME/cs2-ds/start.sh"
grep -Fxq '+sv_setsteamaccount' "$TEST_ROOT/launch-args"
grep -Fxq 'newtoken123456' "$TEST_ROOT/launch-args"
grep -Fxq '+game_type' "$TEST_ROOT/launch-args"
echo 'PASS launcher_reads_gslt_and_mode'

# Execute the installer's apt-timer capture block with only its two fixed
# filesystem paths redirected into the test directory. The installer mock sudo
# cannot exercise this root-owned block itself.
python3 - "$REPO/install.sh" "$TEST_ROOT/timer-state-script" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("sudo bash -c '\n") + len("sudo bash -c '\n")
end = source.index("\n'\nsudo install", start)
block = source[start:end]
block = block.replace('state_dir=/var/lib/cs2-toolkit', 'state_dir="$TEST_ROOT/timer-state"')
block = block.replace('/etc/systemd/system/cs2-os-maintenance@.timer', '"$TEST_ROOT/old-toolkit.timer"')
Path(sys.argv[2]).write_text(block + "\n")
PY
mkdir -p "$TEST_ROOT/timer-bin"
cat > "$TEST_ROOT/timer-bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == is-enabled ]] || exit 1
for timer in ${TEST_ENABLED_TIMERS:-}; do
  if [[ "$timer" == "$2" ]]; then echo enabled; exit 0; fi
done
echo disabled
exit 1
EOF
chmod +x "$TEST_ROOT/timer-bin/systemctl"
TEST_ENABLED_TIMERS=apt-daily.timer PATH="$TEST_ROOT/timer-bin:$PATH" \
  bash "$TEST_ROOT/timer-state-script"
marker="$TEST_ROOT/timer-state/apt-timers.pre-toolkit"
grep -Fxq 'apt-daily.timer' "$marker"
[[ "$(wc -l < "$marker")" -eq 1 ]]
TEST_ENABLED_TIMERS=apt-daily-upgrade.timer PATH="$TEST_ROOT/timer-bin:$PATH" \
  bash "$TEST_ROOT/timer-state-script"
grep -Fxq 'apt-daily.timer' "$marker"
[[ "$(wc -l < "$marker")" -eq 1 ]]
python3 - "$marker" <<'PY'
from pathlib import Path
import stat
import sys

assert stat.S_IMODE(Path(sys.argv[1]).stat().st_mode) == 0o600
PY
rm "$marker"
touch "$TEST_ROOT/old-toolkit.timer"
TEST_ENABLED_TIMERS=apt-daily-upgrade.timer PATH="$TEST_ROOT/timer-bin:$PATH" \
  bash "$TEST_ROOT/timer-state-script" 2> "$TEST_ROOT/legacy-timer-warning"
[[ ! -e "$marker" ]]
grep -Fq 'original apt timer state is unknown' "$TEST_ROOT/legacy-timer-warning"
rm "$TEST_ROOT/old-toolkit.timer"
TEST_ENABLED_TIMERS='' PATH="$TEST_ROOT/timer-bin:$PATH" \
  bash "$TEST_ROOT/timer-state-script"
[[ -f "$marker" && ! -s "$marker" ]]
echo 'PASS apt_timer_state_capture_and_legacy_guard'
