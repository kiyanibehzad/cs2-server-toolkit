#!/bin/bash
# CS2 Admin Toolkit (maps, admin ops, bans, modes, weapons block, chickens)
# Reads config from /home/<user>/cs2-ds/.update.env if present.
# English-only comments. User-level systemd control (no sudo) friendly.
# Adds: dynamic banner (connect line with join password), Join Password menu,
#       Safe update actions, Git self-update hook (G).

set -uo pipefail

# ---------- CONFIG ----------
# Load values from installer (if present)
CS2_USER="${CS2_USER:-$(id -un)}"
CS2_HOME="${CS2_HOME:-/home/$CS2_USER}"
CS2_DIR="${CS2_DIR:-$CS2_HOME/cs2-ds}"
CONF="$CS2_DIR/.update.env"
[[ -f "$CONF" ]] && . "$CONF"

# RCON / networking (fallbacks if not set in .update.env)
RCON_HOST="${HOST_IP:-127.0.0.1}"
RCON_PORT="${PORT:-27015}"
RCON_PASS="${RCON_PASS:-ChangeMe123!}"

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
  red="$(tput setaf 1)"; green="$(tput setaf 2)"; yellow="$(tput setaf 3)"
  blue="$(tput setaf 4)"; magenta="$(tput setaf 5)"; cyan="$(tput setaf 6)"
else
  bold=$'\033[1m'; reset=$'\033[0m'
  red=$'\033[31m'; green=$'\033[32m'; yellow=$'\033[33m'
  blue=$'\033[34m'; magenta=$'\033[35m'; cyan=$'\033[36m'
fi
CLR_MAPS="$cyan"; CLR_ACTIONS="$green"; CLR_BANS="$magenta"
CLR_MODES="$yellow"; CLR_WEAPONS="$blue"; CLR_FUN="$cyan"; CLR_EXIT="$red"; CLR_TITLE="$cyan"

info()  { echo -e "${cyan}[i]${reset} $*"; }
warn()  { echo -e "${yellow}[!]${reset} $*"; }
err()   { echo -e "${red}[x]${reset} $*"; }
ok()    { echo -e "${green}[OK]${reset} $*"; }
pause() { read -rp "$(echo -e "${bold}${blue}Press Enter to continue...${reset} ")" _; }

# ---------- HELPERS ----------
require_cmd() { command -v "$1" >/dev/null 2>&1 || { err "'$1' is not installed"; return 1; }; }
rcon() { require_cmd mcrcon || return 1; mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASS" "$@"; }

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
remove_bots() { rcon "bot_kick"; }
bot_quota()   { rcon "bot_quota $1"; rcon "bot_quota_mode fill"; ok "bot_quota=$1 (fill)"; }
kick_all()    { rcon "kickall"; }

change_map() {
  local map="$1"
  if [[ "$STRICT_CHECK" -eq 1 ]] && ! has_map "$map"; then warn "${map} not found (.bsp/.vpk). Skipping."; return 1; fi
  info "Changing map to: ${bold}$map${reset}"; rcon "changelevel ${map}"
}
update_server() {
  info "Updating server via steamcmd (AppID 730)..."
  if [[ -x "$STEAMCMD" ]]; then
    "$STEAMCMD" +login anonymous +app_update 730 validate +quit
  else
    require_cmd steamcmd || return 1
    steamcmd +login anonymous +app_update 730 validate +quit
  fi
  ok "Update complete."
}

# ---------- USER SERVICE OPS ----------
unit_exists_user() { ensure_user_systemd_env; systemctl --user list-unit-files --type=service | awk '{print $1}' | sed 's/\.service$//' | grep -Fxq "$1"; }
user_unit_is_active() {
  ensure_user_systemd_env
  systemctl --user is-active --quiet "$1" && return 0
  local sub; sub="$(systemctl --user show "$1" -p SubState --value 2>/dev/null || echo inactive)"
  [[ "$sub" == "running" || "$sub" == "start-pre" || "$sub" == "start" || "$sub" == "auto-restart" ]]
}
wait_active_user_unit() {
  local u="$1" tries=20
  while ((tries-- > 0)); do user_unit_is_active "$u" && return 0; sleep 0.5; done
  return 1
}
restart_service() {
  ensure_user_systemd_env
  [[ -z "${SERVICE_NAME:-}" ]] && { warn "SERVICE_NAME is empty."; return 1; }
  if unit_exists_user "$SERVICE_NAME"; then
    if user_unit_is_active "$SERVICE_NAME"; then
      info "Restarting service: ${bold}$SERVICE_NAME${reset}"
      if systemctl --user restart "$SERVICE_NAME"; then
        if wait_active_user_unit "$SERVICE_NAME"; then ok "Service restarted and active."
        else warn "Restart issued, but unit not reporting active yet."; fi
      else err "Restart failed. Recent logs:"; journalctl --user -u "$SERVICE_NAME" -n 80 --no-pager || true; return 1; fi
    else
      warn "Service '$SERVICE_NAME' not active. Trying to start..."
      if systemctl --user start "$SERVICE_NAME"; then
        if wait_active_user_unit "$SERVICE_NAME"; then ok "Service started and active."
        else warn "Start issued, but unit not reporting active yet."; fi
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

backup_cfg() {
  mkdir -p "$BACKUP_DIR"
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  tar -czf "$BACKUP_DIR/cfg-$ts.tar.gz" "$CS2_DIR/game"/*/cfg 2>/dev/null || true
  ok "Backup stored at ${bold}$BACKUP_DIR/cfg-$ts.tar.gz${reset}"
}

# ---------- SAFE UPDATE INTEGRATION ----------
safe_update_now() {
  local script="$CS2_DIR/cs2-safe-update.sh"
  if [[ -x "$script" ]]; then
    /bin/bash -lc "$script"
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
set_mode_core() { rcon "game_type $1"; rcon "game_mode $2"; }
# Competitive MR12 (13-win, OT 3+3); no 5v5 hard cap
set_mode_competitive_MR12() {
  set_mode_core 0 1
  rcon "exec gamemode_competitive.cfg" || true
  rcon "mp_halftime 1"
  rcon "mp_maxrounds 24"
  rcon "mp_overtime_enable 1"
  rcon "mp_overtime_maxrounds 6"
  rcon "mp_buytime 20"
  rcon "mp_freezetime 15"
  rcon "mp_round_restart_delay 7"
  rcon "mp_autokick 0"
}
set_mode_casual()   { set_mode_core 0 0; rcon "exec gamemode_casual.cfg" || true; rcon "mp_maxrounds 15"; rcon "mp_free_armor 1"; rcon "mp_solid_teammates 0"; rcon "mp_autokick 0"; }
set_mode_wingman()  { set_mode_core 0 2; rcon "exec gamemode_competitive.cfg" || true; rcon "mp_maxrounds 16"; }
set_mode_deathmatch(){ rcon "exec gamemode_deathmatch.cfg" || true; rcon "game_type 1"; rcon "game_mode 2"; rcon "mp_maxrounds 0"; rcon "mp_respawn_on_death_ct 1"; rcon "mp_respawn_on_death_t 1"; }
apply_mode_and_reload() {
  local mode="$1" map="${2:-}"
  case "$mode" in
    comp_mr12) set_mode_competitive_MR12 ;;
    casual)    set_mode_casual ;;
    wingman)   set_mode_wingman ;;
    deathmatch) set_mode_deathmatch ;;
    *) err "Unknown mode: $mode"; return 1 ;;
  esac
  if [[ -n "$map" ]]; then change_map "$map"; else rcon "mp_restartgame 1"; fi
  say "Game mode switched to: $mode"; ok "Mode applied: $mode"
}
mode_menu() {
  echo; echo -e "${bold}${CLR_MODES}[Game Mode Presets]${reset}"
  echo -e "  ${CLR_MODES}1)${reset} Competitive MR12 (13-win, OT 3+3)"
  echo -e "  ${CLR_MODES}2)${reset} Casual"
  echo -e "  ${CLR_MODES}3)${reset} Wingman"
  echo -e "  ${CLR_MODES}4)${reset} Deathmatch"
  echo -e "  ${CLR_MODES}0)${reset} Back"; echo
  read -rp "Select: " sel
  case "$sel" in
    1) read -rp "Map to load (blank=keep current, 0=back): " m; [[ "$m" == "0" ]] && return 0; apply_mode_and_reload comp_mr12 "$m" ;;
    2) read -rp "Map to load (blank=keep current, 0=back): " m; [[ "$m" == "0" ]] && return 0; apply_mode_and_reload casual "$m" ;;
    3) read -rp "Map to load (blank=keep current, 0=back): " m; [[ "$m" == "0" ]] && return 0; apply_mode_and_reload wingman "$m" ;;
    4) read -rp "Map to load (blank=keep current, 0=back): " m; [[ "$m" == "0" ]] && return 0; apply_mode_and_reload deathmatch "$m" ;;
    0|"") return 0 ;;
    *) err "Invalid";;
  esac
}

# ---------- WEAPONS BLOCK ----------
weapons_block_show() { info "Current prohibited items:"; rcon "mp_items_prohibited"; }
weapons_block_set()  { local list="$1"; rcon "mp_items_prohibited \"$list\""; ok "Applied: mp_items_prohibited=\"$list\""; }
weapons_block_clear(){ rcon 'mp_items_prohibited ""'; ok "Cleared: no prohibited items."; }
weapons_menu() {
  echo; echo -e "${bold}${CLR_WEAPONS}[Weapons Block]${reset}"
  echo "  1) Show current blocked list"
  echo "  2) Set new blocked list (comma-separated)"
  echo "  3) Clear (allow all)"
  echo "  4) Quick examples"
  echo "  0) Back"; echo
  read -rp "Select: " sel
  case "$sel" in
    1) weapons_block_show ;;
    2) read -rp "Enter items (e.g. weapon_awp,weapon_ssg08; blank=cancel): " L; [[ -z "$L" ]] && info "Cancelled." || weapons_block_set "$L" ;;
    3) weapons_block_clear ;;
    4) echo "Examples:"; echo "  - Ban AWP: weapon_awp"; echo "  - Ban AWP + Scout: weapon_awp,weapon_ssg08"; echo "  - Ban SG + AUG: weapon_sg556,weapon_aug"; echo "  - Ban Negev + XM1014: weapon_negev,weapon_xm1014"; echo ;;
    0|"") return 0 ;;
    *) err "Invalid";;
  esac
}

# ---------- CHICKENS ----------
cheats_current() { rcon "sv_cheats" | grep -Eo '[0-9]+' | head -1 || echo 0; }
chickens_add() {
  local n="${1:-1}"; [[ "$n" =~ ^[0-9]+$ ]] || { err "Invalid number"; return 1; }
  local prev; prev="$(cheats_current)"
  rcon "sv_cheats 1"
  for ((i=0;i<n;i++)); do rcon "ent_create chicken"; done
  rcon "sv_cheats $prev"
  ok "Spawned $n chickens."
}
chickens_clear() {
  local prev; prev="$(cheats_current)"
  rcon "sv_cheats 1"
  rcon "ent_remove chicken"
  rcon "sv_cheats $prev"
  ok "All chickens removed."
}
chickens_menu() {
  echo; echo -e "${bold}${CLR_FUN}[Chickens]${reset}"
  echo "  1) Add chickens (ask count)"
  echo "  2) Clear all chickens"
  echo "  0) Back"; echo
  read -rp "Select: " sel
  case "$sel" in
    1) read -rp "How many? (blank=cancel): " N; [[ -z "$N" ]] && { info "Cancelled."; return 0; }; chickens_add "$N" ;;
    2) chickens_clear ;;
    0|"") return 0 ;;
    *) err "Invalid";;
  esac
}

# ---------- JOIN PASSWORD (sv_password) ----------
# Persist a key=value into .update.env (create or replace)
persist_update_env() {
  local key="$1" val="$2"
  mkdir -p "$(dirname "$CONF")"
  touch "$CONF"
  if grep -qE "^${key}=" "$CONF"; then
    sed -i "s|^${key}=.*|${key}=${val}|g" "$CONF"
  else
    printf '%s=%s\n' "$key" "$val" >> "$CONF"
  fi
}

# Return current join password.
# Priority: JOIN_PASS from .update.env -> live RCON parse
get_join_password() {
  if [[ -n "${JOIN_PASS:-}" ]]; then
    printf '%s' "$JOIN_PASS"
    return
  fi
  local out pw
  out="$(rcon sv_password 2>/dev/null || true)"

  pw="$(printf '%s\n' "$out" \
        | sed -n "s/.*sv_password[[:space:]]*[:=][[:space:]]*'\([^']*\)'.*/\1/p")"
  if [[ -z "$pw" ]]; then
    pw="$(printf '%s\n' "$out" \
          | sed -n 's/.*sv_password[[:space:]]*[:=][[:space:]]*\([^[:space:]]*\).*/\1/p')"
  fi
  printf '%s' "$pw"
}

join_password_menu() {
  while true; do
    local cur; cur="$(get_join_password)"
    echo; echo -e "${bold}${cyan}[Join Password]${reset} (current: '${cur:-<empty>}')"
    echo "  1) Set password"
    echo "  2) Clear (no password)"
    echo "  0) Back"
    read -rp "Select: " s
    case "$s" in
      1)
        read -rp "New password: " np
        [[ -z "$np" ]] && { info "Cancelled."; continue; }
        rcon "sv_password \"$np\""
        persist_update_env "JOIN_PASS" "$np"
        ok "sv_password updated."
        ;;
      2)
        rcon "sv_password \"\""
        persist_update_env "JOIN_PASS" ""
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
  if [[ ! -f "$src" ]]; then
    err "Admin script not found in repo: $src"
    return 1
  fi
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
    echo -e "${bold}${cyan}Connect:${reset} connect ${RCON_HOST}:${RCON_PORT};password ${jp}"
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
  echo
  echo -e "${bold}${CLR_ACTIONS}[Actions]${reset}"
  echo -e "  ${CLR_ACTIONS}s)${reset} Status       ${CLR_ACTIONS}b)${reset} Add bot      ${CLR_ACTIONS}n)${reset} Add bot (CT)   ${CLR_ACTIONS}m)${reset} Add bot (T)"
  echo -e "  ${CLR_ACTIONS}k)${reset} Kick bots    ${CLR_ACTIONS}q)${reset} Set bot quota"
  echo -e "  ${CLR_ACTIONS}u)${reset} Update       ${CLR_ACTIONS}r)${reset} Restart svc  ${CLR_ACTIONS}L)${reset} Live logs"
  echo -e "  ${CLR_ACTIONS}y)${reset} Say message  ${CLR_ACTIONS}a)${reset} Kick ALL     ${CLR_ACTIONS}p)${reset} List installed maps"
  echo -e "  ${CLR_ACTIONS}x)${reset} Backup cfg   ${CLR_ACTIONS}c)${reset} Custom RCON"
  echo -e "  ${CLR_ACTIONS}T)${reset} Safe update now  ${CLR_ACTIONS}t)${reset} Update timer status  ${CLR_ACTIONS}G)${reset} Update toolkit (git)"
  echo
  echo -e "${bold}${cyan}[Access]${reset}"
  echo -e "  ${cyan}J)${reset} Join password menu"
  echo
  echo -e "${bold}${CLR_BANS}[Bans]${reset}"
  echo -e "  ${CLR_BANS}B)${reset} List banned  ${CLR_BANS}U)${reset} Unban (select from list)"
  echo
  echo -e "${bold}${CLR_MODES}[Modes]${reset}"
  echo -e "  ${CLR_MODES}g)${reset} Game mode presets (MR12 etc.)"
  echo
  echo -e "${bold}${CLR_WEAPONS}[Weapons]${reset}"
  echo -e "  ${CLR_WEAPONS}w)${reset} Weapons block menu"
  echo
  echo -e "${bold}${CLR_FUN}[Fun]${reset}"
  echo -e "  ${CLR_FUN}h)${reset} Chickens menu"
  echo
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
      s) status || true ;;
      b) add_bot auto || true ;;
      n) add_bot ct   || true ;;
      m) add_bot t    || true ;;
      k) remove_bots  || true ;;
      q) read -rp "Bot quota (blank=cancel): " N; [[ -z "$N" ]] && info "Cancelled." || { [[ "$N" =~ ^[0-9]+$ ]] && bot_quota "$N" || err "Invalid number"; } ;;
      u) update_server || true ;;
      r) restart_service || true ;;
      L) live_logs || true ;;
      y) read -rp "Message (blank=cancel): " MSG; [[ -z "$MSG" ]] && info "Cancelled." || say "$MSG" ;;
      a) kick_all || true ;;
      p) list_installed_maps || true ;;
      x) backup_cfg || true ;;
      c) read -rp "RCON cmd (blank=cancel): " RC; [[ -z "$RC" ]] && info "Cancelled." || rcon "$RC" ;;
      B) list_banned || true ;;
      U) unban_select || true ;;
      g) mode_menu ;;
      w) weapons_menu ;;
      h) chickens_menu ;;
      J|j) join_password_menu ;;
      T) safe_update_now || true ;;
      t) show_update_timer || true ;;
      G) update_toolkit_git || true ;;
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
  kick-all) kick_all ;;
  update) update_server ;;
  restart) restart_service ;;
  backup) backup_cfg ;;
  list-maps) list_installed_maps ;;
  change-map) change_map "${1:-de_dust2}" ;;
  rcon) rcon "$@" ;;
  list-banned) list_banned ;;
  unban-select) unban_select ;;
  join-pass-menu) join_password_menu ;;
  safe-update) safe_update_now ;;
  show-timer) show_update_timer ;;
  update-toolkit) update_toolkit_git ;;
  *) ui_loop ;;
esac
