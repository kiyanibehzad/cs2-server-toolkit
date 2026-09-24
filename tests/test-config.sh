#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/game/csgo/cfg"
printf 'hostname "Test"\n' > "$TEST_ROOT/game/csgo/cfg/cs2server.cfg"
cat > "$TEST_ROOT/bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_ROOT/bin/flock"
export PATH="$TEST_ROOT/bin:$PATH" CS2_DIR="$TEST_ROOT"
TOOL="$REPO/scripts/cs2-config.sh"

[[ "$(bash "$TOOL" set 'AWP, Negev, weapon_awp, M249, G3SG1, SCAR-20')" == \
  'weapon_awp,weapon_negev,weapon_m249,weapon_g3sg1,weapon_scar20' ]]
[[ "$(bash "$TOOL" ids)" == '9,28,14,11,38' ]]
[[ "$(bash "$TOOL" set 'AWP,9,Negev,28')" == 'weapon_awp,weapon_negev' ]]
[[ "$(bash "$TOOL" ids)" == '9,28' ]]
bash "$TOOL" set 'AWP, Negev, M249, G3SG1, SCAR-20' >/dev/null
grep -Fxq 'mp_items_prohibited "9,28,14,11,38"' "$TEST_ROOT/game/csgo/cfg/cs2_toolkit.cfg"
grep -Fxq 'exec cs2_toolkit.cfg' "$TEST_ROOT/game/csgo/cfg/cs2server.cfg"
bash "$TOOL" sync
[[ "$(grep -Fc 'exec cs2_toolkit.cfg' "$TEST_ROOT/game/csgo/cfg/gamemode_competitive_server.cfg")" -eq 1 ]]
[[ "$(grep -Fc 'exec cs2_toolkit.cfg' "$TEST_ROOT/game/csgo/cfg/gamemode_rush_server.cfg")" -eq 1 ]]
[[ "$(bash "$TOOL" show)" == 'weapon_awp,weapon_negev,weapon_m249,weapon_g3sg1,weapon_scar20' ]]
if bash "$TOOL" set 'AWP; quit' >/dev/null 2>&1; then
  echo 'FAIL unsafe weapon input accepted'; exit 1
fi
[[ "$(bash "$TOOL" ids)" == '9,28,14,11,38' ]]
bash "$TOOL" set '' >/dev/null
grep -Fxq 'mp_items_prohibited ""' "$TEST_ROOT/game/csgo/cfg/cs2_toolkit.cfg"
[[ -z "$(bash "$TOOL" show)" ]]
echo 'PASS persistent_weapon_config'
