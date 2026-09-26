#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/game"
printf 'RCON_PASS=test\nHOST_IP=127.0.0.1\nPORT=27015\nSERVER_PASS=private-test-password\n' > "$TEST_ROOT/game/.update.env"

cat > "$TEST_ROOT/bin/mcrcon" <<'EOF'
#!/usr/bin/env bash
case "${!#}" in
  status)
    printf 'hostname : Test CS2\nversion : 1.41.8.5/14185\nplayers : 2 humans, 1 bots (10 max)\n'
    ;;
  host_map) printf 'host_map : de_dust2\n' ;;
  game_type) printf 'game_type = 0\n' ;;
  game_mode) printf 'game_mode = 1\n' ;;
  sv_skirmish_id) printf 'sv_skirmish_id = 0\n' ;;
  sv_password) printf 'sv_password = "private-test-password"\n' ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/mcrcon"

export CS2_DIR="$TEST_ROOT/game" PATH="$TEST_ROOT/bin:$PATH" NO_COLOR=1 TERM=xterm
ADMIN="$REPO/scripts/cs2-admin-v2.sh"

"$ADMIN" preview > "$TEST_ROOT/preview"
grep -Fq 'CS2 Server Toolkit  /  v2 BETA' "$TEST_ROOT/preview"
grep -Fq 'Game: Competitive  |  Map: de_dust2' "$TEST_ROOT/preview"
grep -Fq 'connect 127.0.0.1:27015; password ******** (hidden)' "$TEST_ROOT/preview"
! grep -Fq 'private-test-password' "$TEST_ROOT/preview"
[[ "$(wc -l < "$TEST_ROOT/preview")" -le 20 ]]

printf '1\n\n4\n\n5\n\n6\n\nq\n' | "$ADMIN" ui > "$TEST_ROOT/navigation"
for section in 'Maps & game modes' 'Players & access' 'Server tools' 'Extras'; do
  grep -Fq "$section" "$TEST_ROOT/navigation"
done
grep -Fq '[OK] Bye' "$TEST_ROOT/navigation"

echo 'PASS admin_v2_preview_and_navigation'
