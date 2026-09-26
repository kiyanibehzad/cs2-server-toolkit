#!/bin/bash
# CS2 Admin Toolkit (maps, admin ops, bans, modes, bots, voice, weapons, fun)
# Reads config from /home/<user>/cs2-ds/.update.env if present.

set -uo pipefail

# ---------- CONFIG ----------
# Load values from installer (if present)
CS2_USER="${CS2_USER:-$(id -un)}"
CS2_HOME="${CS2_HOME:-$HOME}"
CS2_DIR="${CS2_DIR:-$CS2_HOME/cs2-ds}"
CONF="$CS2_DIR/.update.env"
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && . "$CONF"

# RCON / networking (fallbacks if not set in .update.env)
RCON_HOST="${HOST_IP:-127.0.0.1}"
RCON_PORT="${PORT:-27015}"
RCON_PASS="${RCON_PASS:-}"

# Paths and service
STEAMCMD="${STEAMCMD:-$CS2_HOME/steamcmd/steamcmd.sh}"
SERVICE_NAME="${SERVICE_NAME:-cs2-ds}"   # user-level systemd unit (without .service)
BACKUP_DIR="$CS2_DIR/backups"
STRICT_CHECK=${STRICT_CHECK:-1}

# Weapon cfg names (created if missing)
CFG_WEAPONS_DEFAULT="weapons_all_default.cfg"
CFG_WEAPONS_PISTOLS="weapons_pistols_only.cfg"
CFG_WEAPONS_NO_RIFLES="weapons_no_rifles.cfg"

# ---------- DYNAMIC BANNER SETTINGS ----------
# External status link template. You can override via .update.env or env:
# e.g., STATUS_URL_TPL="https://ismygameserver.online/valve/%s:%s"
STATUS_URL_TPL="${STATUS_URL_TPL:-https://ismygameserver.online/valve/%s:%s}"

compute_status_url() {
  printf "$STATUS_URL_TPL" "$RCON_HOST" "$RCON_PORT"
}

# Banner cached fields (updated on each draw)
BANNER_HOSTNAME=""
BANNER_VERSION=""
BANNER_PLAYERS=""

# ---------- COLORS ----------
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
  bold="$(tput bold)"; reset="$(tput sgr0)"
  red="$(tput setaf 1)"; green="$(tput setaf 2)"
  yellow="$(tput setaf 3)"
  blue="$(tput setaf 4)"; magenta="$(tput setaf 5)"; cyan="$(tput setaf 6)"; white="$(tput setaf 7)"
else
  bold=$'\033[1m'; reset=$'\033[0m'
  red=$'\033[31m'; green=$'\033[32m'; yellow=$'\033[33m'
  blue=$'\033[34m'; magenta=$'\033[35m'; cyan=$'\033[36m'
  white=$'\033[37m'
fi

# ---------- COLOR SCHEME ----------
# Each menu section uses a different color for better visual distinction.
# 1=red, 2=green, 3=yellow, 4=blue, 5=magenta, 6=cyan, 7=white

CLR_MAPS="$cyan"         # Map hotkeys section (cyan)
CLR_BOTS="$yellow"       # Bot controls section (yellow)
CLR_ACTIONS="$green"     # Quick actions (green)
CLR_TOOLS="$blue"        # Server tools (blue)
CLR_BANS="$magenta"      # Ban management (magenta)
CLR_MODES="$red"         # Game modes (red)
CLR_WEAPONS="$white"     # Weapons blocking (white)
CLR_FUN="$cyan"          # Fun section (chickens etc.) (cyan)
CLR_VOICE="$green"       # Live voice routing
CLR_EXIT="$red"          # Exit (red)
CLR_TITLE="$magenta"     # Title/header (magenta)

info()  { echo -e "${cyan}[i]${reset} $*"; }
warn()  { echo -e "${yellow}[!]${reset} $*"; }
err()   { echo -e "${red}[x]${reset} $*"; }
ok()    { echo -e "${green}[OK]${reset} $*"; }
pause() { read -rp "$(echo -e "${bold}${blue}Press Enter to continue...${reset} ")" _; }

# ---------- HELPERS ----------
require_cmd() { command -v "$1" >/dev/null 2>&1 || { err "'$1' is not installed"; return 1; }; }
RCON_CLIENT="${RCON_CLIENT:-$CS2_DIR/cs2-rcon.py}"
CONFIG_TOOL="${CONFIG_TOOL:-$CS2_DIR/cs2-config.sh}"
rcon() {
  local output result=0
  [[ -n "$RCON_PASS" ]] || { err "RCON password is missing"; return 1; }
  if [[ -x "$RCON_CLIENT" ]]; then
    output="$(RCON_PASS="$RCON_PASS" "$RCON_CLIENT" -H "$RCON_HOST" -P "$RCON_PORT" "$@")" || result=$?
  else
    require_cmd mcrcon || return 1
    output="$(mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASS" "$@")" || result=$?
  fi
  [[ -z "$output" ]] || printf '%s\n' "$output"
  if printf '%s\n' "$output" | grep -Eqi "Unknown (command|variable)|couldn't exec|failed to execute"; then
    return 1
  fi
  return "$result"
}

has_map() {
  local map="$1"
  find "$CS2_DIR/game" -type f \( -path "*/maps/${map}.bsp" -o -path "*/maps/${map}.vpk" -o -path "*/maps/${map}_*.vpk" \) \
    -print -quit 2>/dev/null | grep -q .
}
list_installed_maps() {
  find "$CS2_DIR/game" -type f -path "*/maps/*" \( -name "*.bsp" -o -name "*.vpk" \) -printf "%f\n" 2>/dev/null \
    | sed -E 's/\.(bsp|vpk)$//' | sed -E 's/_vanity$//' | sort -u
}
map_for_key() {
  case "$1" in
    1) echo "de_dust2";; 2) echo "de_mirage";; 3) echo "de_inferno";; 4) echo "de_nuke";;
    5) echo "de_overpass";; 6) echo "de_vertigo";; 7) echo "de_ancient";; 8) echo "de_anubis";;
    9) echo "de_cache";; 0) echo "de_train";; *) echo "";;
  esac
}
cfg_path_guess() {
  [[ -d "$CS2_DIR/game/csgo/cfg" ]] && { echo "$CS2_DIR/game/csgo/cfg"; return; }
  [[ -d "$CS2_DIR/game/cs2/cfg"  ]] && { echo "$CS2_DIR/game/cs2/cfg";  return; }
  echo "$CS2_DIR/game/csgo/cfg"
}
ensure_cfg_exists() {
  local name="$1"; local p; p="$(cfg_path_guess)/$name"
  [[ -f "$p" ]] && return 0
  mkdir -p "$(dirname "$p")"
  case "$name" in
    "$CFG_WEAPONS_DEFAULT")
      printf '%s\n' \
        'mp_buy_anywhere 0' \
        'mp_buy_anywhere_warmup 0' \
        'mp_buytime 20' \
        'mp_ct_default_primary ""' \
        'mp_t_default_primary ""' > "$p"
      ;;
    "$CFG_WEAPONS_PISTOLS")
      printf '%s\n' \
        'mp_buytime 15' \
        'mp_ct_default_primary ""' \
        'mp_t_default_primary ""' > "$p"
      ;;
    "$CFG_WEAPONS_NO_RIFLES")
      printf '%s\n' \
        'mp_buytime 20' \
        'mp_ct_default_primary ""' \
        'mp_t_default_primary ""' > "$p"
      ;;
  esac
  ok "Created sample cfg: $p"
}
exec_cfg() { local name="$1"; ensure_cfg_exists "$name"; rcon "exec $name"; }

# ---------- USER-SERVICE ENV ----------
ensure_user_systemd_env() {
  local uid; uid="$(id -u)"
  [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "${XDG_RUNTIME_DIR:-/nonexist}" ]] && [[ -d "/run/user/$uid" ]] && export XDG_RUNTIME_DIR="/run/user/$uid"
  [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "/run/user/$uid/bus" ]] && export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
}

# ---------- CORE OPS ----------
status()      { rcon status; }
say()         { rcon "say $*"; }
add_bot()     { case "${1:-auto}" in ct) rcon "bot_add_ct";; t) rcon "bot_add_t";; *) rcon "bot_add";; esac; }
remove_bots() { bot_set_count 0; }
bot_quota()   { bot_set_count "$1"; }
kick_all()    { rcon "kickall"; }

current_map() {
  # Try to parse current map from `status` output
  local out m
  out="$(rcon status 2>/dev/null || true)"

  # First try: parse "SV:  [1: de_dust2 | ...]"
  m="$(echo "$out" \
      | sed -n 's/.*SV:  \[1: \([^ |]\+\).*/\1/p' \
      | head -n1)"

  # Fallback: parse a "map  : de_..." style line if present
  if [[ -z "$m" ]]; then
    m="$(echo "$out" \
        | awk -F': ' '/^map[[:space:]]*:/{print $2}' \
        | awk '{print $1}' \
        | head -n1)"
  fi

  echo "$m"
}

change_map() {
  local map="$1" out cur tries

  # Make sure server is up and RCON responds
  ensure_server_running || return 1

  if [[ "$STRICT_CHECK" -eq 1 ]] && ! has_map "$map"; then
    warn "${map} not found (.bsp/.vpk). Skipping."
    return 1
  fi

  info "Changing map to: ${bold}$map${reset}"
  out="$(rcon "changelevel ${map}" 2>&1 || true)"

  # If server reports not running (rare race), try to start and use 'map' as fallback
  if echo "$out" | grep -qi "Server not running"; then
    warn "Server reported not running; restarting user service and retrying."
    restart_service || true
    wait_rcon_ready || true
    out="$(rcon "map ${map}" 2>&1 || true)"
  fi

  # Verify with retries (server needs a second to settle)
  tries=16
  while ((tries-- > 0)); do
    sleep 0.5
    cur="$(current_map)"
    if [[ "$cur" == "$map" ]]; then
      ok "Map changed to ${map}."
      return 0
    fi
  done

  warn "Map may not have changed (current: '${cur:-unknown}')."
  return 1
}

update_server() {
  info "Checking players and updating server (AppID 730)..."
  "$CS2_DIR/cs2-safe-update.sh" --force
}

# ---------- USER SERVICE OPS ----------
unit_exists_user() { ensure_user_systemd_env; systemctl --user list-unit-files --type=service | awk '{print $1}' | sed 's/\.service$//' | grep -Fxq "$1"; }
user_unit_is_active() {
  ensure_user_systemd_env
  systemctl --user is-active --quiet "$1"
}
wait_active_user_unit() {
  local u="$1" tries=60
  while ((tries-- > 0)); do user_unit_is_active "$u" && return 0; sleep 1; done
  return 1
}
restart_service() {
  ensure_user_systemd_env
  [[ -z "${SERVICE_NAME:-}" ]] && { warn "SERVICE_NAME is empty."; return 1; }
  if unit_exists_user "$SERVICE_NAME"; then
    if user_unit_is_active "$SERVICE_NAME"; then
      info "Restarting service: ${bold}$SERVICE_NAME${reset}"
      if systemctl --user restart "$SERVICE_NAME"; then
        if wait_active_user_unit "$SERVICE_NAME" && wait_rcon_ready; then ok "Service restarted and RCON ready."
        else err "Restart issued, but server is not ready."; return 1; fi
      else err "Restart failed. Recent logs:"; journalctl --user -u "$SERVICE_NAME" -n 80 --no-pager || true; return 1; fi
    else
      warn "Service '$SERVICE_NAME' not active. Trying to start..."
      if systemctl --user start "$SERVICE_NAME"; then
        if wait_active_user_unit "$SERVICE_NAME" && wait_rcon_ready; then ok "Service started and RCON ready."
        else err "Start issued, but server is not ready."; return 1; fi
      else err "Start failed. Recent logs:"; journalctl --user -u "$SERVICE_NAME" -n 80 --no-pager || true; return 1; fi
    fi
  else
    err "User service '${SERVICE_NAME}.service' not found."
    info "Tip: unit at ~/.config/systemd/user/${SERVICE_NAME}.service ; run: systemctl --user daemon-reload"
    return 1
  fi
}
live_logs() {
  ensure_user_systemd_env
  [[ -z "${SERVICE_NAME:-}" ]] && { warn "SERVICE_NAME is empty; cannot follow logs."; return 1; }
  unit_exists_user "$SERVICE_NAME" || { err "User service '${SERVICE_NAME}.service' not found."; return 1; }
  require_cmd journalctl || return 1
  info "Following logs for ${bold}$SERVICE_NAME${reset} (Ctrl+C to exit)..."
  journalctl --user -u "$SERVICE_NAME" -f -n 200
}

# ---------- SERVER STATUS HELPERS ----------
# Wait until RCON responds (server truly up)
wait_rcon_ready() {
  local tries=60
  while ((tries-- > 0)); do
    if rcon status >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

# Ensure user-level systemd service is up and RCON is reachable
ensure_server_running() {
  ensure_user_systemd_env
  if user_unit_is_active "$SERVICE_NAME"; then
    wait_rcon_ready || { warn "RCON not ready yet."; return 1; }
    return 0
  fi
  warn "Service '$SERVICE_NAME' not active. Starting..."
  systemctl --user start "$SERVICE_NAME" || { err "Failed to start service."; return 1; }
  if ! wait_active_user_unit "$SERVICE_NAME"; then
    warn "Unit started but not reporting active yet."
  fi
  wait_rcon_ready || { err "RCON still not ready after start."; return 1; }
  ok "Service running and RCON ready."
}

# More robust current map detection (use host_map first)
current_map() {
  local out m
  out="$(rcon "host_map" 2>/dev/null || true)"
  m="$(echo "$out" | awk -F': ' '/host_map[[:space:]]*:/{print $2}' | awk '{print $1}' | head -n1)"
  if [[ -n "$m" ]]; then echo "$m"; return 0; fi
  out="$(rcon status 2>/dev/null || true)"
  m="$(echo "$out" | sed -n 's/.*SV:  \[1: \([^ |]\+\).*/\1/p' | head -n1)"
  [[ -n "$m" ]] && { echo "$m"; return 0; }
  m="$(echo "$out" | awk -F': ' '/^map[[:space:]]*:/{print $2}' | awk '{print $1}' | head -n1)"
  echo "$m"
}

backup_cfg() {
  mkdir -p "$BACKUP_DIR"
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  if (umask 077; tar -czf "$BACKUP_DIR/cfg-$ts.tar.gz" "$CS2_DIR/game"/*/cfg); then
    ok "Backup stored at ${bold}$BACKUP_DIR/cfg-$ts.tar.gz${reset}"
  else
    err "Config backup failed."
    return 1
  fi
}

# ---------- SAFE UPDATE INTEGRATION ----------
safe_update_now() {
  local script="$CS2_DIR/cs2-safe-update.sh"
  if [[ -x "$script" ]]; then
    "$script" --check
  else
    warn "cs2-safe-update.sh not found or not executable at $script"
  fi
}
show_update_timer() {
  ensure_user_systemd_env
  echo -e "${bold}${CLR_ACTIONS}[Update timer status]${reset}"
  systemctl --user list-timers --all | awk 'NR==1 || /cs2-checkupdate\.timer/ {print}'
  echo
  echo -e "${bold}${CLR_ACTIONS}[Last cs2-checkupdate.service logs]${reset}"
  journalctl --user -u cs2-checkupdate.service -n 20 --no-pager || true
}

# ---------- BANS ----------
list_banned() { info "Listing banned users..."; rcon "listid"; }
unban_select() {
  local raw choice tmp; raw="$(list_banned || true)"; tmp="$(mktemp)"
  echo "$raw" | grep -Eo '(7656119[0-9]{10}|STEAM_[0-5]:[01]:[0-9]+|\[U:[0-9]:[0-9]+\])' | sort -u > "$tmp"
  [[ ! -s "$tmp" ]] && { warn "No banned users found."; echo "$raw"; rm -f "$tmp"; return 1; }
  echo -e "${bold}${magenta}Banned users:${reset}"; nl -ba "$tmp"
  read -rp "Select number to unban (0=back): " choice
  [[ -z "$choice" || "$choice" == 0 ]] && { info "Back."; rm -f "$tmp"; return 0; }
  [[ "$choice" =~ ^[0-9]+$ ]] || { err "Invalid selection."; rm -f "$tmp"; return 1; }
  local total; total="$(wc -l < "$tmp")"; (( choice>=1 && choice<=total )) || { err "Out of range."; rm -f "$tmp"; return 1; }
  local sid; sid="$(sed -n "${choice}p" "$tmp")"; rm -f "$tmp"
  info "Unbanning: ${bold}$sid${reset}"; rcon "removeid $sid"; rcon "writeid" || true; ok "Done."
}

# ---------- MODES ----------

# Valve selects the mode-specific cfg during map loading from these four
# values. Set them before changelevel; then verify and apply toolkit overrides.
set_mode_core() {
  rcon "sv_game_mode_flags 0" >/dev/null || return 1
  rcon "sv_skirmish_id $3" >/dev/null || return 1
  rcon "game_type $1" >/dev/null || return 1
  rcon "game_mode $2" >/dev/null || return 1
}

convar_value() {
  local name="$1" output
  output="$(rcon "$name")" || return 1
  printf '%s\n' "$output" | sed -nE "s/^[[:space:]]*${name}[[:space:]]*=[[:space:]]*(.*)$/\1/p" | head -n 1
}

# An explicit bot choice is saved in cs2_toolkit.cfg, which runs after Valve's
# mode cfg on each map load. With no saved choice, mode defaults remain intact.
bot_saved_settings() {
  local saved
  BOT_SAVED_COUNT='' BOT_SAVED_DIFFICULTY='' BOT_SAVED_LAST=2
  [[ -x "$CONFIG_TOOL" ]] || return 0
  saved="$("$CONFIG_TOOL" bots-show)" || return 1
  [[ -n "$saved" ]] && read -r BOT_SAVED_COUNT BOT_SAVED_DIFFICULTY BOT_SAVED_LAST <<< "$saved"
  return 0
}

bot_live_settings() {
  local line
  BOT_LIVE_COUNT="$(convar_value bot_quota)" || return 1
  BOT_LIVE_MODE="$(convar_value bot_quota_mode)" || return 1
  BOT_LIVE_DIFFICULTY="$(convar_value bot_difficulty)" || return 1
  BOT_LIVE_MODE="${BOT_LIVE_MODE//\"/}"
  [[ -n "$BOT_LIVE_COUNT" && -n "$BOT_LIVE_MODE" && -n "$BOT_LIVE_DIFFICULTY" ]] || return 1
  line="$(rcon status 2>/dev/null | grep -E '^[[:space:]]*players[[:space:]]*:' | head -n 1)" || true
  BOT_ACTIVE="$(printf '%s\n' "$line" | sed -nE 's/.*[, ]([0-9]+) bots([ ,(]|$).*/\1/p')"
  [[ "$BOT_LIVE_COUNT" =~ ^[0-9]+$ ]] || BOT_LIVE_COUNT=0
  [[ "$BOT_LIVE_DIFFICULTY" =~ ^[0-3]$ ]] || BOT_LIVE_DIFFICULTY=2
}

bot_count_for_control() {
  if [[ "$BOT_LIVE_MODE" == normal ]]; then
    printf '%s' "$BOT_LIVE_COUNT"
  elif [[ "$BOT_ACTIVE" =~ ^[0-9]+$ ]]; then
    printf '%s' "$BOT_ACTIVE"
  else
    printf '%s' "$BOT_LIVE_COUNT"
  fi
}

bot_apply() {
  local count="$1" difficulty="$2" last="$3" recreate="${4:-no}"
  [[ "$count" =~ ^(0|[1-9]|[1-5][0-9]|6[0-4])$ ]] || { err 'Bot count must be 0-64.'; return 1; }
  [[ "$difficulty" =~ ^[0-3]$ ]] || { err 'Difficulty must be 0-3.'; return 1; }
  [[ -x "$CONFIG_TOOL" ]] || { err 'Toolkit config helper is missing.'; return 1; }
  "$CONFIG_TOOL" bots-set "$count" "$difficulty" "$last" || return 1
  if [[ "$count" == 0 || "$recreate" == yes ]]; then
    rcon 'bot_quota 0' >/dev/null || return 1
    rcon 'bot_kick' >/dev/null || return 1
  fi
  rcon 'exec cs2_toolkit.cfg' >/dev/null || return 1
  verify_convar bot_quota_mode normal || return 1
  verify_convar bot_quota "$count" || return 1
  verify_convar sv_auto_adjust_bot_difficulty 0 || return 1
  verify_convar bot_difficulty "$difficulty" || return 1
}

bot_set_count() {
  local count="$1" difficulty last
  bot_saved_settings || return 1
  bot_live_settings || return 1
  difficulty="${BOT_SAVED_DIFFICULTY:-$BOT_LIVE_DIFFICULTY}"
  last="$BOT_SAVED_LAST"
  [[ "$count" != 0 ]] && last="$count"
  bot_apply "$count" "$difficulty" "$last" || return 1
  ok "Bot target: $count (normal mode)."
}

bot_add_many() {
  local amount="$1" current target
  [[ "$amount" =~ ^([1-9]|[1-5][0-9]|6[0-4])$ ]] || { err 'Enter a number from 1 to 64.'; return 1; }
  bot_live_settings || return 1
  current="$(bot_count_for_control)"
  target=$((current + amount))
  (( target <= 64 )) || { err 'The bot target cannot exceed 64.'; return 1; }
  bot_set_count "$target"
}

bot_enable() {
  local target
  bot_saved_settings || return 1
  bot_live_settings || return 1
  target="${BOT_SAVED_COUNT:-$(bot_count_for_control)}"
  [[ "$target" =~ ^[0-9]+$ ]] || target=0
  (( target > 0 )) || target="$BOT_SAVED_LAST"
  bot_set_count "$target"
}

bot_difficulty_set() {
  local difficulty="$1" count last
  [[ "$difficulty" =~ ^[0-3]$ ]] || { err 'Difficulty: 0 easy, 1 normal, 2 hard, 3 expert.'; return 1; }
  bot_saved_settings || return 1
  bot_live_settings || return 1
  count="${BOT_SAVED_COUNT:-$(bot_count_for_control)}"
  last="$BOT_SAVED_LAST"
  (( count > 0 )) && last="$count"
  bot_apply "$count" "$difficulty" "$last" yes || return 1
  ok "Bot difficulty: $difficulty. Existing bots were recreated at the new level."
}

bot_menu() {
  local choice amount
  while true; do
    clear
    echo -e "${bold}${CLR_BOTS}=== Bot Management ===${reset}"
    if bot_live_settings; then
      echo "Active: ${BOT_ACTIVE:-unknown} | Target: $BOT_LIVE_COUNT | Mode: $BOT_LIVE_MODE | Difficulty: $BOT_LIVE_DIFFICULTY"
    else
      warn 'Could not read live bot settings.'
    fi
    echo
    echo '  1) Turn on bots / restore last count'
    echo '  2) Turn off and kick all bots'
    echo '  3) Add multiple bots'
    echo '  4) Set exact bot count'
    echo '  5) Change difficulty (recreates current bots)'
    echo '  0) Back'
    echo
    read -rp 'Choose: ' choice || return 0
    case "$choice" in
      1) bot_enable || true ;;
      2) bot_set_count 0 || true ;;
      3) read -rp 'How many to add (1-64, blank=cancel): ' amount || return 0
         [[ -z "$amount" ]] || bot_add_many "$amount" || true ;;
      4) read -rp 'Exact bot count (0-64, blank=cancel): ' amount || return 0
         [[ -z "$amount" ]] || bot_set_count "$amount" || true ;;
      5) read -rp 'Difficulty (0 easy, 1 normal, 2 hard, 3 expert; blank=cancel): ' amount || return 0
         [[ -z "$amount" ]] || bot_difficulty_set "$amount" || true ;;
      0|'') return 0 ;;
      *) warn 'Unknown option.' ;;
    esac
    echo; pause
  done
}

verify_convar() {
  local name="$1" expected="$2" actual
  actual="$(convar_value "$name")" || return 1
  case "$actual" in
    true) actual=1 ;; false) actual=0 ;;
  esac
  if [[ "$actual" != "$expected" ]]; then
    err "$name expected $expected, got ${actual:-no response}"
    return 1
  fi
}

# ---------- LIVE VOICE ----------
# These are live server cvars only. No toolkit cfg or mode defaults are edited.
VOICE_NAMES=(sv_full_alltalk sv_alltalk sv_deadtalk sv_talk_enemy_living sv_talk_enemy_dead sv_auto_full_alltalk_during_warmup_half_end)
voice_read() {
  local name value
  VOICE_VALUES=()
  for name in "${VOICE_NAMES[@]}"; do
    value="$(convar_value "$name")" || return 1
    case "$value" in true|1) value=1 ;; false|0) value=0 ;; *) err "Could not read $name"; return 1 ;; esac
    VOICE_VALUES+=("$value")
  done
}

voice_status() {
  voice_read || return 1
  local mode='Custom'
  case "${VOICE_VALUES[*]}" in
    '0 0 0 0 0 0') mode='Team only' ;;
    '0 0 1 0 0 0') mode='Team together' ;;
    '0 0 0 0 1 0') mode='Dead across teams' ;;
    '0 1 1 0 0 0') mode='Both teams' ;;
    '1 1 1 0 0 0') mode='Everyone, including spectators' ;;
  esac
  printf 'Current: %s\n' "$mode"
  printf 'Full/all teams: %s/%s | Dead to living: %s | Enemy living/dead: %s/%s | Auto warmup: %s\n' \
    "${VOICE_VALUES[0]}" "${VOICE_VALUES[1]}" "${VOICE_VALUES[2]}" \
    "${VOICE_VALUES[3]}" "${VOICE_VALUES[4]}" "${VOICE_VALUES[5]}"
}

voice_mode() {
  local mode="${1:-}" i failed=0
  local -a desired previous
  case "$mode" in
    team)      desired=(0 0 0 0 0 0) ;;
    team-dead) desired=(0 0 1 0 0 0) ;;
    dead-all)  desired=(0 0 0 0 1 0) ;;
    both-teams) desired=(0 1 1 0 0 0) ;;
    all)       desired=(1 1 1 0 0 0) ;;
    *) err 'Voice mode must be team, team-dead, dead-all, both-teams, or all.'; return 2 ;;
  esac
  voice_read || { err 'Could not read the current voice settings.'; return 1; }
  previous=("${VOICE_VALUES[@]}")
  for i in "${!VOICE_NAMES[@]}"; do
    [[ "${previous[i]}" == "${desired[i]}" ]] && continue
    rcon "${VOICE_NAMES[i]} ${desired[i]}" >/dev/null || { failed=1; break; }
    verify_convar "${VOICE_NAMES[i]}" "${desired[i]}" || { failed=1; break; }
  done
  if ((failed)); then
    warn 'Voice change failed; restoring the previous values.'
    for i in "${!VOICE_NAMES[@]}"; do
      rcon "${VOICE_NAMES[i]} ${previous[i]}" >/dev/null || warn "Could not restore ${VOICE_NAMES[i]}"
    done
    return 1
  fi
  ok "Voice mode: $mode (live, no restart)."
}

voice_menu() {
  local choice
  while true; do
    echo
    echo -e "${bold}${CLR_VOICE}=== Live Voice ===${reset}"
    voice_status || warn 'Live voice settings unavailable.'
    echo '  1) Team only: living and dead separated'
    echo '  2) Team together: dead can speak to living teammates'
    echo '  3) Dead players across both teams; living stay team-only'
    echo '  4) Both teams together (T + CT)'
    echo '  5) Everyone together, including spectators'
    echo '  0) Back'
    read -rp 'Choose: ' choice || return 0
    case "$choice" in
      1) voice_mode team || true ;;
      2) voice_mode team-dead || true ;;
      3) voice_mode dead-all || true ;;
      4) voice_mode both-teams || true ;;
      5) voice_mode all || true ;;
      0|"") return 0 ;;
      *) err 'Invalid choice.' ;;
    esac
  done
}

ingame_menu() {
  local choice steam_id name
  local helper="$CS2_DIR/cs2-ingame-menu.sh"
  [[ -x "$helper" ]] || { err 'In-game menu installer is missing. Reinstall the toolkit.'; return 1; }
  while true; do
    echo
    echo -e "${bold}${CLR_TOOLS}=== In-game Admin Menu ===${reset}"
    echo '  1) Install or update the in-game menu'
    echo '  2) Show installation status'
    echo '  3) List admins'
    echo '  4) Add admin by SteamID64'
    echo '  5) Remove admin by SteamID64'
    echo '  0) Back'
    read -rp 'Choose: ' choice || return 0
    case "$choice" in
      1)
        read -rp 'First admin SteamID64 (blank to keep existing admins): ' steam_id || return 0
        "$helper" install "$steam_id" || true
        ;;
      2) "$helper" status || true ;;
      3) "$helper" list-admins || true ;;
      4)
        read -rp 'SteamID64: ' steam_id || return 0
        read -rp 'Admin label (blank for automatic): ' name || return 0
        "$helper" add-admin "$steam_id" "$name" || true
        ;;
      5)
        read -rp 'SteamID64 to remove: ' steam_id || return 0
        "$helper" remove-admin "$steam_id" || true
        ;;
      0|'') return 0 ;;
      *) err 'Invalid choice.' ;;
    esac
  done
}

# Common settings: no autobalance or team limits. Rush keeps Valve's fill bots.
apply_common_team_settings() {
  local mode="${1:-}"
  rcon "mp_autoteambalance 0" >/dev/null || return 1
  rcon "mp_limitteams 0" >/dev/null || return 1

  if [[ "$mode" == rush ]]; then
    # gamemode_rush.cfg ships with two fill bots; retain that behavior.
    rcon "bot_quota_mode fill" >/dev/null || return 1
    rcon "bot_quota 2" >/dev/null || return 1
  else
    rcon "bot_quota 0" >/dev/null || return 1
    rcon "bot_join_after_player 0" >/dev/null || return 1
    rcon "bot_quota_mode normal" >/dev/null || return 1
    rcon "bot_kick" >/dev/null || return 1
  fi
}

# Apply a complete identity before loading the map. Values are derived from
# Valve's CS2 game mode table; Retakes is a Casual skirmish (ID 12).
mode_identity() {
  local mode="$1" type game skirmish=0
  case "$mode" in
    comp_mr12) type=0; game=1 ;;
    casual) type=0; game=0 ;;
    wingman) type=0; game=2 ;;
    deathmatch) type=1; game=2 ;;
    retakes) type=0; game=0; skirmish=12 ;;
    armsrace) type=1; game=0 ;;
    rush) type=0; game=6 ;;
    *) err "Unknown mode: $mode"; return 1 ;;
  esac
  set_mode_core "$type" "$game" "$skirmish" || return 1
  MODE_TYPE="$type" MODE_GAME="$game" MODE_SKIRMISH="$skirmish"
}

apply_mode_rules() {
  local mode="$1" command
  local -a commands=(
    'mp_autokick 0'
    'mp_shoot_dropped_grenades 1'
  )
  if [[ "$mode" == comp_mr12 ]]; then
    commands+=(
      'mp_maxrounds 24' 'mp_halftime 1'
      'mp_overtime_enable 1' 'mp_overtime_maxrounds 6'
      'mp_overtime_startmoney 10000'
      'mp_overtime_halftime_pausetimer 1'
      'mp_match_can_clinch 1'
    )
  elif [[ "$mode" != wingman ]]; then
    commands+=('mp_overtime_enable 0')
  fi
  if [[ "$mode" == armsrace ]]; then
    commands+=(
      'mp_teammates_are_enemies 0'
      'mp_respawn_on_death_t 1' 'mp_respawn_on_death_ct 1'
    )
  elif [[ "$mode" != deathmatch ]]; then
    commands+=('mp_teammates_are_enemies 0' 'mp_respawn_on_death_t 0' 'mp_respawn_on_death_ct 0')
  fi
  for command in "${commands[@]}"; do
    rcon "$command" >/dev/null || { err "Failed: $command"; return 1; }
  done
  apply_common_team_settings "$mode" || return 1
  rcon 'exec cs2_toolkit.cfg' >/dev/null || return 1
  verify_convar game_type "$MODE_TYPE" || return 1
  verify_convar game_mode "$MODE_GAME" || return 1
  verify_convar sv_skirmish_id "$MODE_SKIRMISH" || return 1
  verify_convar sv_game_mode_flags 0 || return 1
  if [[ "$mode" == comp_mr12 ]]; then
    verify_convar mp_overtime_enable 1 || return 1
    verify_convar mp_overtime_maxrounds 6 || return 1
  fi
}

apply_mode_and_reload() {
  local mode="$1" map="${2:-}" cur
  ensure_server_running || { err "Server not ready; cannot apply mode."; return 1; }
  [[ "$mode" == rush && -z "$map" ]] && map=rush_001
  if [[ -n "$map" && "$STRICT_CHECK" -eq 1 ]] && ! has_map "$map"; then
    err "Map '$map' is not installed; mode was not changed."
    return 1
  fi
  [[ -x "$CONFIG_TOOL" ]] || { err "Toolkit config helper is missing."; return 1; }
  "$CONFIG_TOOL" sync || { err "Could not prepare persistent settings."; return 1; }
  mode_identity "$mode" || return 1
  cur="${map:-$(current_map)}"
  [[ -n "$cur" ]] || { err "Current map is unknown; mode was not applied."; return 1; }
  change_map "$cur" || return 1
  apply_mode_rules "$mode" || { err "Mode changed but a rule failed; inspect server state."; return 1; }
  say "Game mode switched to: $mode" || warn "Mode changed; announcement failed."
  ok "Mode applied: $mode"
}

restore_default() { apply_mode_and_reload comp_mr12 de_dust2; }

armsrace_map() {
  local map="$1"
  case "$map" in
    ar_pool_day|ar_shoots|ar_baggage) ;;
    *) err "Unknown Arms Race map: $map"; return 1 ;;
  esac
  if ! has_map "$map"; then
    err "Map '$map' is not installed; mode was not changed."
    return 1
  fi
  apply_mode_and_reload armsrace "$map"
}

armsrace_map_menu() {
  local sel map label
  echo; echo -e "${bold}${CLR_MAPS}[Arms Race Maps (map + preset)]${reset}"
  for sel in 1 2 3; do
    case "$sel" in
      1) map=ar_pool_day; label="Pool Day" ;;
      2) map=ar_shoots; label="Shoots" ;;
      3) map=ar_baggage; label="Baggage" ;;
    esac
    if has_map "$map"; then
      echo -e "  ${CLR_MAPS}${sel})${reset} ${label} (${map})"
    else
      echo -e "  ${CLR_MAPS}${sel})${reset} ${label} (${map}) [not installed]"
    fi
  done
  echo -e "  ${CLR_MAPS}0)${reset} Back"
  echo
  read -rp "Select: " sel
  case "$sel" in
    1) armsrace_map ar_pool_day ;;
    2) armsrace_map ar_shoots ;;
    3) armsrace_map ar_baggage ;;
    0|"") return 0 ;;
    *) err "Invalid selection"; return 1 ;;
  esac
}

rush_map() {
  local map="$1"
  case "$map" in
    rush_001) ;;
    *) err "Unknown Rush map: $map"; return 1 ;;
  esac
  if ! has_map "$map"; then
    err "Map '$map' is not installed; mode was not changed."
    return 1
  fi
  apply_mode_and_reload rush "$map"
}

rush_map_menu() {
  local sel
  echo; echo -e "${bold}${CLR_MAPS}[Rush Maps (map + preset)]${reset}"
  if has_map rush_001; then
    echo -e "  ${CLR_MAPS}1)${reset} rush_001 (official Rush map)"
  else
    echo -e "  ${CLR_MAPS}1)${reset} rush_001 [not installed]"
  fi
  echo -e "  ${CLR_MAPS}0)${reset} Back"
  echo
  read -rp "Select: " sel
  case "$sel" in
    1) rush_map rush_001 ;;
    0|"") return 0 ;;
    *) err "Invalid selection"; return 1 ;;
  esac
}

# Menu
mode_menu() {
  echo; echo -e "${bold}${CLR_MODES}[Game Mode Presets]${reset}"
  echo -e "  ${CLR_MODES}1)${reset} Competitive"
  echo -e "  ${CLR_MODES}2)${reset} Casual"
  echo -e "  ${CLR_MODES}3)${reset} Wingman"
  echo -e "  ${CLR_MODES}4)${reset} Deathmatch"
  echo -e "  ${CLR_MODES}5)${reset} Retakes"
  echo -e "  ${CLR_MODES}6)${reset} Arms Race"
  echo -e "  ${CLR_MODES}7)${reset} Rush (rush_001)"
  echo -e "  ${CLR_MODES}0)${reset} Back"
  echo
  read -rp "Select: " sel
  case "$sel" in
    1) apply_mode_and_reload comp_mr12 ;;
    2) apply_mode_and_reload casual ;;
    3) apply_mode_and_reload wingman ;;
    4) apply_mode_and_reload deathmatch ;;
    5) apply_mode_and_reload retakes ;;
    6) apply_mode_and_reload armsrace ;;
    7) rush_map rush_001 ;;
    0|"") return 0 ;;
    *) err "Invalid selection" ;;
  esac
}

# ======================================================================
# CUSTOM MODES: Creation + Per-Mode Server CFG Editing
# ======================================================================

# Sanitizes a user-provided mode name (letters/numbers/spaces)
sanitize_slug() {
  local s="$1"
  s="${s//[^a-zA-Z0-9_ -]/}"          # allow only safe chars
  s="$(echo "$s" | sed -E 's/[[:space:]]+/_/g')"  # convert spaces to _
  echo "$s" | tr 'A-Z' 'a-z'          # lowercase
}

# Ask for integer with default
ask_int_default() {
  local prompt="$1" def="$2" ans
  read -rp "$prompt [$def]: " ans
  [[ -z "$ans" ]] && { echo "$def"; return; }
  [[ "$ans" =~ ^-?[0-9]+$ ]] && { echo "$ans"; return; }
  echo "$def"
}

# ----------------------------------------------------------------------
# C) Create custom mode file (*.cfg)
# ----------------------------------------------------------------------
create_custom_mode() {
  local cfg_dir; cfg_dir="$(cfg_path_guess)/custom_modes"
  mkdir -p "$cfg_dir"

  echo
  echo -e "${bold}${CLR_MODES}[Custom Mode Builder]${reset}"

  local raw slug
  read -rp "Mode name (letters/numbers/spaces): " raw
  slug="$(sanitize_slug "$raw")"

  [[ -z "$slug" ]] && { err "Invalid / empty name."; return 1; }

  local out="$cfg_dir/${slug}.cfg"

  if [[ -f "$out" ]]; then
    read -rp "File exists. Overwrite? (y/N): " yn
    [[ "$yn" =~ ^[Yy]$ ]] || { warn "Cancelled."; return; }
  fi

  echo
  echo "Choose base preset:"
  echo "  1) Competitive base"
  echo "  2) Casual base"
  echo "  3) Wingman base"
  echo "  4) Deathmatch base"
  echo "  5) Empty (no preset)"
  read -rp "Select [1-5]: " base

  case "$base" in
    1) base_exec="exec gamemode_competitive.cfg" ;;
    2) base_exec="exec gamemode_casual.cfg" ;;
    3) base_exec="exec gamemode_competitive2v2.cfg" ;;
    4) base_exec="exec gamemode_deathmatch.cfg" ;;
    5|*) base_exec="" ;;
  esac

  echo
  echo "Enter convars (press Enter for default):"

  # Default suggestions
  case "$base" in
    1) gt=0; gm=1 ;;   # comp
    2) gt=0; gm=0 ;;   # casual
    3) gt=0; gm=2 ;;   # wingman
    4) gt=1; gm=2 ;;   # dm
    *) gt=0; gm=0 ;;
  esac

  gt="$(ask_int_default "game_type" "$gt")"
  gm="$(ask_int_default "game_mode" "$gm")"

  maxrounds="$(ask_int_default "mp_maxrounds" "24")"
  halftime="$(ask_int_default "mp_halftime (0/1)" "1")"
  overtime_enable="$(ask_int_default "mp_overtime_enable (0/1)" "1")"
  overtime_max="$(ask_int_default "mp_overtime_maxrounds" "6")"
  buytime="$(ask_int_default "mp_buytime" "20")"
  freezetime="$(ask_int_default "mp_freezetime" "15")"
  rrdelay="$(ask_int_default "mp_round_restart_delay" "7")"
  autokick="$(ask_int_default "mp_autokick (0/1)" "0")"
  ff="$(ask_int_default "mp_friendlyfire (0/1)" "0")"
  startmoney="$(ask_int_default "mp_startmoney" "800")"
  warmup_time="$(ask_int_default "mp_warmuptime" "20")"

  {
    echo "// Custom mode: $slug"
    [[ -n "$base_exec" ]] && echo "$base_exec"
    echo "game_type $gt"
    echo "game_mode $gm"
    echo "mp_maxrounds $maxrounds"
    echo "mp_halftime $halftime"
    echo "mp_overtime_enable $overtime_enable"
    echo "mp_overtime_maxrounds $overtime_max"
    echo "mp_buytime $buytime"
    echo "mp_freezetime $freezetime"
    echo "mp_round_restart_delay $rrdelay"
    echo "mp_autokick $autokick"
    echo "mp_friendlyfire $ff"
    echo "mp_startmoney $startmoney"
    echo "mp_warmuptime $warmup_time"
    echo "echo \"[custom_modes] Loaded ${slug}.cfg\""
  } > "$out"

  ok "Saved: $out"

  read -rp "Apply now? (y/N): " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    local current
    current="$(current_map)"
    [[ -n "$current" ]] || { err "Current map is unknown; mode file was saved but not applied."; return 1; }
    rcon "exec custom_modes/${slug}.cfg" || return 1
    change_map "$current" || return 1
    rcon "exec custom_modes/${slug}.cfg" || return 1
    rcon "mp_restartgame 1" || return 1
    ok "Custom mode applied."
  fi
}

# ----------------------------------------------------------------------
# S) Edit *_server.cfg per mode
# ----------------------------------------------------------------------
_edit_file_with_vi() { local f="$1"; "${EDITOR:-vi}" "$f"; }
_ensure_file() { local f="$1"; [[ -f "$f" ]] || { mkdir -p "$(dirname "$f")"; : > "$f"; }; }

edit_mode_server_cfg_menu() {
  local cfgdir; cfgdir="$(cfg_path_guess)"
  local target base sel

  while true; do
    echo
    echo -e "${bold}${CLR_MODES}[Edit *_server.cfg per mode]${reset}"
    echo "  1) competitive   -> gamemode_competitive_server.cfg"
    echo "  2) casual        -> gamemode_casual_server.cfg"
    echo "  3) wingman       -> gamemode_competitive2v2_server.cfg"
    echo "  4) deathmatch    -> gamemode_deathmatch_server.cfg"
    echo "  5) retakes       -> gamemode_retakecasual_server.cfg"
    echo "  6) arms race     -> gamemode_armsrace_server.cfg"
    echo "  7) rush          -> gamemode_rush_server.cfg"
    echo "  8) custom name..."
    echo "  0) Back"

    read -rp "Select: " sel

    case "$sel" in
      1) target="$cfgdir/gamemode_competitive_server.cfg" ;;
      2) target="$cfgdir/gamemode_casual_server.cfg" ;;
      3) target="$cfgdir/gamemode_competitive2v2_server.cfg" ;;
      4) target="$cfgdir/gamemode_deathmatch_server.cfg" ;;
      5) target="$cfgdir/gamemode_retakecasual_server.cfg" ;;
      6) target="$cfgdir/gamemode_armsrace_server.cfg" ;;
      7) target="$cfgdir/gamemode_rush_server.cfg" ;;
      8)
         read -rp "Enter base name (example: surf -> surf_server.cfg): " base
         [[ -z "$base" ]] && continue
         target="$cfgdir/${base}_server.cfg"
         ;;
      0|"") return ;;
      *) err "Invalid"; continue ;;
    esac

    _ensure_file "$target"
    info "Opening: $target"
    _edit_file_with_vi "$target"
    ok "Saved."

    restart_service || warn "Restart failed; check logs."
  done
}

# ---------- WEAPONS BLOCK ----------
weapons_block_show() {
  [[ -x "$CONFIG_TOOL" ]] || { err "Toolkit config helper is missing."; return 1; }
  info "Saved list: $("$CONFIG_TOOL" show)"
  info "Live value:"
  rcon "mp_items_prohibited"
}
weapons_block_set() {
  local list ids live
  [[ -x "$CONFIG_TOOL" ]] || { err "Toolkit config helper is missing."; return 1; }
  list="$("$CONFIG_TOOL" set "$1")" || return 1
  ids="$("$CONFIG_TOOL" ids)" || return 1
  if ! rcon "mp_items_prohibited \"$ids\""; then
    err "Saved the list, but the live server rejected it. Check RCON."
    return 1
  fi
  live="$(convar_value mp_items_prohibited)" || return 1
  live="${live//\"/}"
  live="${live// /}"
  [[ "$live" == "$ids" ]] || {
    err "Saved restriction, but live value differs (expected ${ids:-empty}, got ${live:-empty})."
    return 1
  }
  ok "Saved and applied: ${list:-none} (indices: ${ids:-none})"
}
weapons_block_clear() { weapons_block_set ''; }
weapons_menu() {
  echo; echo -e "${bold}${CLR_WEAPONS}[Weapons Block]${reset}"
  echo "  1) Show current blocked list"
  echo "  2) Set saved blocked list (names or aliases)"
  echo "  3) Clear (allow all)"
  echo "  4) Quick examples"
  echo "  0) Back"; echo
  read -rp "Select: " sel
  case "$sel" in
    1) weapons_block_show ;;
    2) read -rp "Enter items (e.g. weapon_awp,weapon_ssg08; blank=cancel): " L; [[ -z "$L" ]] && info "Cancelled." || weapons_block_set "$L" ;;
    3) weapons_block_clear ;;
    4) echo "Examples:"; echo "  - AWP, Negev, M249, G3SG1, SCAR-20"; echo "  - weapon_awp,weapon_ssg08"; echo ;;
    0|"") return 0 ;;
    *) err "Invalid";;
  esac
}

# ---------- FUN: CHICKENS / GRAVITY / SPEED ----------

# Get current sv_cheats value (0/1); an unreadable value is an error.
cheats_current() {
  local value
  value="$(convar_value sv_cheats)" || return 1
  case "$value" in
    0|false) echo 0 ;; 1|true) echo 1 ;;
    *) err "Cannot read sv_cheats: ${value:-empty}"; return 1 ;;
  esac
}

with_temporary_cheats() (
  local previous
  previous="$(cheats_current)" || exit 1
  restore_cheats() {
    trap - EXIT
    rcon "sv_cheats $previous" >/dev/null || {
      echo "Could not restore sv_cheats" >&2
      exit 1
    }
  }
  trap restore_cheats EXIT
  trap 'exit 130' INT TERM
  rcon 'sv_cheats 1' >/dev/null || exit 1
  "$@"
)

spawn_chickens() {
  local n="$1" i
  for ((i=0; i<n; i++)); do
    rcon 'ent_create chicken' >/dev/null || return 1
  done
}

# ----- Chickens -----
fun_chickens_add() {
  local n="${1:-1}"
  [[ "$n" =~ ^[0-9]+$ ]] || { err "Invalid number"; return 1; }

  (( n <= 50 )) || { err "Maximum is 50 chickens."; return 1; }
  with_temporary_cheats spawn_chickens "$n" || return 1
  ok "Spawned $n chickens."
}

fun_chickens_clear() {
  with_temporary_cheats rcon 'ent_remove chicken' || return 1
  ok "All chickens removed."
}

fun_chickens_menu() {
  echo
  echo -e "${bold}${CLR_FUN}[Chickens]${reset}"
  echo "  1) Add chickens (ask count)"
  echo "  2) Clear all chickens"
  echo "  0) Back"
  echo
  read -rp "Select: " sel
  case "$sel" in
    1)
      read -rp "How many? (blank=cancel): " N
      [[ -z "$N" ]] && { info "Cancelled."; return 0; }
      fun_chickens_add "$N"
      ;;
    2)
      fun_chickens_clear
      ;;
    0|"")
      return 0
      ;;
    *)
      err "Invalid"
      ;;
  esac
}

# ----- Gravity -----
# Safe wrapper to set gravity
fun_gravity_set() {
  local g="$1"
  [[ "$g" =~ ^[0-9]+$ ]] || { err "Invalid gravity value"; return 1; }
  rcon "sv_gravity $g" >/dev/null || return 1
  ok "sv_gravity set to $g"
}

fun_gravity_menu() {
  echo
  echo -e "${bold}${CLR_FUN}[Gravity]${reset}"
  echo "  1) Normal (800)"
  echo "  2) Low gravity (400)"
  echo "  3) Moon gravity (200)"
  echo "  0) Back"
  echo
  read -rp "Select: " sel
  case "$sel" in
    1) fun_gravity_set 800 ;;
    2) fun_gravity_set 400 ;;
    3) fun_gravity_set 200 ;;
    0|"") return 0 ;;
    *) err "Invalid" ;;
  esac
}

# ----- Speed (host_timescale) -----
fun_speed_set() {
  local scale="$1"
  with_temporary_cheats rcon "host_timescale $scale" >/dev/null || return 1
  ok "host_timescale set to $scale; sv_cheats restored."
}

fun_speed_menu() {
  echo
  echo -e "${bold}${CLR_FUN}[Speed / Time]${reset}"
  echo "  1) Normal speed (1.0)"
  echo "  2) Fast (1.5)"
  echo "  3) Slow motion (0.5)"
  echo "  0) Back"
  echo
  read -rp "Select: " sel
  case "$sel" in
    1) fun_speed_set 1.0 ;;
    2) fun_speed_set 1.5 ;;
    3) fun_speed_set 0.5 ;;
    0|"") return 0 ;;
    *) err "Invalid" ;;
  esac
}

# ----- Main FUN menu -----
fun_menu() {
  while true; do
    echo
    echo -e "${bold}${CLR_FUN}[Fun menu]${reset}"
    echo "  1) Chickens"
    echo "  2) Gravity"
    echo "  3) Speed / Slow motion"
    echo "  0) Back"
    echo
    read -rp "Select: " sel
    case "$sel" in
      1) fun_chickens_menu ;;
      2) fun_gravity_menu ;;
      3) fun_speed_menu ;;
      0|"") return 0 ;;
      *) err "Invalid" ;;
    esac
  done
}

# ---------- JOIN PASSWORD (sv_password) ----------
# Persist a key=value into .update.env (create or replace)
persist_update_env() {
  local key="$1" val="$2"
  local tmp
  tmp="$(mktemp "${CONF}.XXXXXX")" || return 1
  if [[ -f "$CONF" ]]; then
    grep -v "^${key}=" "$CONF" > "$tmp" || true
  fi
  printf '%s=%q\n' "$key" "$val" >> "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$CONF"
}

persist_server_password() {
  local password="$1" cfg tmp
  cfg="$(cfg_path_guess)/cs2server.cfg"
  [[ -f "$cfg" ]] || { err "Server config missing: $cfg"; return 1; }
  tmp="$(mktemp "${cfg}.XXXXXX")" || return 1
  awk -v password="$password" '
    $1 == "sv_password" { print "sv_password \"" password "\""; found=1; next }
    { print }
    END { if (!found) print "sv_password \"" password "\"" }
  ' "$cfg" > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp"
  mv -f "$tmp" "$cfg"
}

# Always prefer live RCON value; fall back to .update.env
get_join_password() {
  local out pw
  out="$(rcon sv_password 2>/dev/null || true)"

  # formats to handle:
  #  sv_password : 'mypw'
  #  sv_password : mypw
  #  "sv_password" = "mypw"
  pw="$(printf '%s\n' "$out" \
        | sed -n "s/.*sv_password[[:space:]]*[:=][[:space:]]*'\\([^']*\\)'.*/\\1/p")"
  if [[ -z "$pw" ]]; then
    pw="$(printf '%s\n' "$out" \
          | sed -n 's/.*sv_password[[:space:]]*[:=][[:space:]]*\"\\([^\"]*\\)\".*/\\1/p')"
  fi
  if [[ -z "$pw" ]]; then
    pw="$(printf '%s\n' "$out" \
          | sed -n 's/.*sv_password[[:space:]]*[:=][[:space:]]*\\([^[:space:]]*\\).*/\\1/p')"
  fi

  # If live is empty, fall back to env variable (if any)
  if [[ -z "$pw" && -n "${SERVER_PASS:-}" ]]; then
    printf '%s' "$SERVER_PASS"
  else
    printf '%s' "$pw"
  fi
}

join_password_menu() {
  while true; do
    local cur; cur="$(get_join_password)"
    echo; echo -e "${bold}${cyan}[Join Password]${reset} (current: $( [[ -n "$cur" ]] && echo set || echo empty ))"
    echo "  1) Set password"
    echo "  2) Clear (no password)"
    echo "  0) Back"
    read -rp "Select: " s
    case "$s" in
      1)
        read -r -s -p "New password: " np; echo
        [[ -z "$np" ]] && { info "Cancelled."; continue; }
        [[ "$np" != *[\;\"\\]* && ! "$np" =~ [[:cntrl:]] ]] || { err "Invalid character in password."; continue; }
        rcon "sv_password \"$np\"" || { err "Failed to set sv_password"; continue; }
        persist_update_env "SERVER_PASS" "$np" || { err "Could not save settings"; continue; }
        persist_server_password "$np" || { err "Could not save server config"; continue; }
        SERVER_PASS="$np"
        ok "sv_password updated."
        ;;
      2)
        rcon "sv_password \"\"" || { err "Failed to clear sv_password"; continue; }
        persist_update_env "SERVER_PASS" "" || { err "Could not save settings"; continue; }
        persist_server_password "" || { err "Could not save server config"; continue; }
        SERVER_PASS=""
        ok "Join password cleared."
        ;;
      0|"") return 0 ;;
      *) err "Invalid";;
    esac
  done
}

# Update banner data from "status"
fetch_banner_stats() {
  local out
  out="$(rcon status 2>/dev/null || true)"
  BANNER_HOSTNAME="$(echo "$out" | awk -F': ' '/^hostname[[:space:]]*:/{print $2}' | head -n1)"
  [[ -z "$BANNER_HOSTNAME" ]] && BANNER_HOSTNAME="n/a"
  BANNER_VERSION="$(echo "$out" | awk '/^version[[:space:]]*:/{print $3}' | head -n1)"
  [[ -z "$BANNER_VERSION" ]] && BANNER_VERSION="n/a"
  BANNER_PLAYERS="$(echo "$out" | awk '/^players[[:space:]]*:/{sub(/^players[[:space:]]*:[[:space:]]*/,""); print}' | head -n1)"
  [[ -z "$BANNER_PLAYERS" ]] && BANNER_PLAYERS="n/a"
}

# ---------- TOOLKIT SELF-UPDATE ----------
update_toolkit_git() {
  require_cmd git || return 1
  local repo="${TOOLKIT_REPO:-$HOME/cs2-server-toolkit}"
  local src="${TOOLKIT_SCRIPT:-$repo/scripts/cs2-admin.sh}"
  local self
  self="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
  if [[ ! -d "$repo/.git" ]]; then
    err "Toolkit repo not found at $repo"
    return 1
  fi
  info "Pulling latest toolkit from Git..."
  (cd "$repo" && git pull --rebase) || { err "git pull failed"; return 1; }
  if [[ ! -f "$src" || ! -f "$repo/scripts/cs2-config.sh" ]]; then
    err 'Admin or config helper is missing from the toolkit repo.'
    return 1
  fi
  install -m 0755 "$repo/scripts/cs2-config.sh" "$CONFIG_TOOL" || { err "Config helper install failed"; return 1; }
  install -m 0755 "$src" "$self" || { err "Install failed"; return 1; }
  ok "Admin script updated from Git."
  echo "Reloading menu..."
  exec "$self"
}

# ---------- UI ----------

banner() {
  fetch_banner_stats
  local status_url; status_url="$(compute_status_url)"
  local jp; jp="$(get_join_password)"

  clear
  echo -e "${bold}${CLR_TITLE}=== CS2 Quick Admin ===${reset}"
  echo
  if [[ -n "$jp" ]]; then
    echo -e "${bold}${cyan}Connect:${reset} connect ${RCON_HOST}:${RCON_PORT}; password ******** (hidden)"
  else
    echo -e "${bold}${cyan}Connect:${reset} connect ${RCON_HOST}:${RCON_PORT}"
  fi
  echo -e "${bold}${cyan}Hostname:${reset} ${BANNER_HOSTNAME}"
  echo -e "${bold}${cyan}Version:${reset} ${BANNER_VERSION}"
  echo -e "${bold}${cyan}Players:${reset} ${BANNER_PLAYERS}"
  echo -e "${bold}${cyan}Status URL:${reset} ${status_url}"
  echo
  echo -e "${bold}${CLR_MAPS}[Map Hotkeys]${reset}"
  echo -e "  ${CLR_MAPS}1)${reset} de_dust2     ${CLR_MAPS}2)${reset} de_mirage    ${CLR_MAPS}3)${reset} de_inferno  ${CLR_MAPS}4)${reset} de_nuke"
  echo -e "  ${CLR_MAPS}5)${reset} de_overpass  ${CLR_MAPS}6)${reset} de_vertigo   ${CLR_MAPS}7)${reset} de_ancient  ${CLR_MAPS}8)${reset} de_anubis"
  echo -e "  ${CLR_MAPS}9)${reset} de_cache     ${CLR_MAPS}0)${reset} de_train"
  echo -e "  ${CLR_MAPS}p)${reset} List installed maps"
  echo -e "  ${CLR_MAPS}A)${reset} Arms Race maps (Pool Day / Shoots / Baggage + preset)"
  echo -e "  ${CLR_MAPS}R)${reset} Rush map (rush_001 + preset)"
  echo -e "  ${CLR_MAPS}H)${reset} Home: Competitive MR12 + de_dust2"
  echo
  echo -e "${bold}${CLR_BOTS}[Bots]${reset}"
  echo -e "  ${CLR_BOTS}b)${reset} Bot management (on/off, count, add many, difficulty)"
  echo
  echo -e "${bold}${CLR_VOICE}[Voice]${reset}"
  echo -e "  ${CLR_VOICE}v)${reset} Live voice control (teams / dead / everyone)"
  echo
  echo -e "${bold}${CLR_ACTIONS}[Actions]${reset}"
  echo -e "  ${CLR_ACTIONS}s)${reset} Status       ${CLR_ACTIONS}y)${reset} Say message  ${CLR_ACTIONS}a)${reset} Kick ALL"
  echo
  echo -e "${bold}${CLR_TOOLS}[Tools]${reset}"
  echo -e "  ${CLR_TOOLS}u)${reset} Force update (if empty)  ${CLR_TOOLS}r)${reset} Restart svc  ${CLR_TOOLS}L)${reset} Live logs"
  echo -e "  ${CLR_TOOLS}x)${reset} Backup cfg   ${CLR_TOOLS}c)${reset} Custom RCON"
  echo -e "  ${CLR_TOOLS}T)${reset} Safe update check  ${CLR_TOOLS}t)${reset} Update timer status  ${CLR_TOOLS}G)${reset} Update admin menu (git)"
  echo -e "  ${CLR_TOOLS}K)${reset} In-game admin menu: install / manage admins"
  echo -e "  ${CLR_TOOLS}h)${reset} Health check"
  echo
  echo -e "${bold}${cyan}[Access]${reset}"
  echo -e "  ${cyan}J)${reset} Join password menu"
  echo
  echo -e "${bold}${CLR_BANS}[Bans]${reset}"
  echo -e "  ${CLR_BANS}B)${reset} List banned  ${CLR_BANS}U)${reset} Unban (select from list)"
  echo
  echo -e "${bold}${CLR_MODES}[Modes]${reset}"
  echo -e "  ${CLR_MODES}P)${reset} Game mode presets (Comp_MR12 / Casual / Wingman / DM)"
  echo -e "  ${CLR_MODES}C)${reset} Create custom mode (.cfg)"
  echo -e "  ${CLR_MODES}S)${reset} Edit *_server.cfg per mode (Edit+restart)"
  echo
  echo -e "${bold}${CLR_WEAPONS}[Weapons]${reset}"
  echo -e "  ${CLR_WEAPONS}w)${reset} Weapons block menu"
  echo
  echo -e "${bold}${CLR_FUN}[Fun]${reset}"
  echo -e "  ${CLR_FUN}f)${reset} Fun menu (chickens / gravity / speed)"
  echo
  echo -e "${bold}${CLR_EXIT}[EXIT]${reset}"
  echo -e "  ${CLR_EXIT}e)${reset} Exit"
  echo
  echo -ne "${bold}${blue}Press a key:${reset} "
}

ui_loop() {
  while true; do
    banner
    IFS= read -r -n1 key
    echo
    case "$key" in
      1|2|3|4|5|6|7|8|9|0) map="$(map_for_key "$key")"; [[ -n "$map" ]] && change_map "$map" || warn "Unknown key" ;;
      p) list_installed_maps || true ;;
      A) armsrace_map_menu || true ;;
      R) rush_map_menu || true ;;
      H) restore_default || true ;;

      # Bots
      b) bot_menu; continue ;;
      v) voice_menu; continue ;;

      # Actions
      s) status || true ;;
      y) read -rp "Message (blank=cancel): " MSG; [[ -z "$MSG" ]] && info "Cancelled." || say "$MSG" ;;
      a) kick_all || true ;;

      # Tools
      u) update_server || true ;;
      r) restart_service || true ;;
      L) live_logs || true ;;
      x) backup_cfg || true ;;
      c) read -rp "RCON cmd (blank=cancel): " RC; [[ -z "$RC" ]] && info "Cancelled." || rcon "$RC" ;;
      T) safe_update_now || true ;;
      t) show_update_timer || true ;;
      h) "$CS2_DIR/cs2-health.sh" || true ;;
      G) update_toolkit_git || true ;;
      K) ingame_menu; continue ;;

      # Access / Bans / Modes / Weapons / Fun
      J|j) join_password_menu ;;
      B) list_banned || true ;;
      U) unban_select || true ;;
      P) mode_menu ;;
      C) create_custom_mode ;;
      S) edit_mode_server_cfg_menu ;;
      w) weapons_menu ;;
      f) fun_menu ;;

      # Exit
      e) ok "Bye"; break ;;
      *) warn "Unknown key: $key" ;;
    esac
    echo; pause
  done
}

# ---------- CLI ----------
cmd="${1:-ui}"; shift || true
case "$cmd" in
  ui|menu) ui_loop ;;
  status) status ;;
  say) say "$@" ;;
  add-bot) add_bot "${1:-auto}" ;;
  remove-bots) remove_bots ;;
  bot-quota) bot_quota "${1:-0}" ;;
  bot-on) bot_enable ;;
  bot-off) bot_set_count 0 ;;
  bots-add) bot_add_many "${1:-}" ;;
  bot-difficulty) bot_difficulty_set "${1:-}" ;;
  bot-menu) bot_menu ;;
  voice-mode) voice_mode "${1:-}" ;;
  voice-status) voice_status ;;
  voice-menu) voice_menu ;;
  ingame-menu) ingame_menu ;;
  ingame-install) "$CS2_DIR/cs2-ingame-menu.sh" install "${1:-}" "${2:-}" ;;
  ingame-status) "$CS2_DIR/cs2-ingame-menu.sh" status ;;
  ingame-admin-add) "$CS2_DIR/cs2-ingame-menu.sh" add-admin "${1:-}" "${2:-}" ;;
  ingame-admin-remove) "$CS2_DIR/cs2-ingame-menu.sh" remove-admin "${1:-}" ;;
  kick-all) kick_all ;;
  update) update_server ;;
  restart) restart_service ;;
  backup) backup_cfg ;;
  list-maps) list_installed_maps ;;
  change-map) change_map "${1:-de_dust2}" ;;
  armsrace-map) armsrace_map "${1:-}" ;;
  rush-map) rush_map "${1:-}" ;;
  default) restore_default ;;
  mode) apply_mode_and_reload "${1:-}" "${2:-}" ;;
  rcon) rcon "$@" ;;
  list-banned) list_banned ;;
  unban-select) unban_select ;;
  join-pass-menu) join_password_menu ;;
  safe-update) safe_update_now ;;
  show-timer) show_update_timer ;;
  health) "$CS2_DIR/cs2-health.sh" ;;
  weapons-show) weapons_block_show ;;
  weapons-set) weapons_block_set "${1:-}" ;;
  weapons-clear) weapons_block_clear ;;
  fun-chickens) fun_chickens_add "${1:-1}" ;;
  fun-chickens-clear) fun_chickens_clear ;;
  fun-gravity) fun_gravity_set "${1:-}" ;;
  fun-speed) fun_speed_set "${1:-}" ;;
  update-toolkit) update_toolkit_git ;;
  *) ui_loop ;;
esac
