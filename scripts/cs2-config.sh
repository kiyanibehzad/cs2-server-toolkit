#!/usr/bin/env bash
# Persistent toolkit settings. Never edit Valve's gamemode_*.cfg defaults.
set -euo pipefail

CS2_DIR="${CS2_DIR:-$HOME/cs2-ds}"
CFG_DIR="$CS2_DIR/game/csgo/cfg"
STATE_DIR="$CS2_DIR/toolkit-config"
STATE="$STATE_DIR/blocked-weapons.txt"
GENERATED="$CFG_DIR/cs2_toolkit.cfg"
HOOK='exec cs2_toolkit.cfg'

# CS2's mp_items_prohibited takes item definition indices, not entity names.
# Keep recognizable names in the saved state and convert only known items.
weapon_index() {
  case "$1" in
    weapon_awp) echo 9 ;; weapon_negev) echo 28 ;;
    weapon_m249) echo 14 ;; weapon_g3sg1) echo 11 ;;
    weapon_scar20) echo 38 ;; weapon_ssg08) echo 40 ;;
    weapon_sg556) echo 39 ;; weapon_aug) echo 8 ;;
    weapon_xm1014) echo 25 ;;
    [1-9]|[1-9][0-9]|[1-9][0-9][0-9]) echo "$1" ;;
    *) return 1 ;;
  esac
}

normalize_weapons() {
  local item index result='' seen_ids=',' raw
  local -a items=()
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  raw="${raw//,/ }"
  [[ "$raw" =~ [^[:space:]] ]] || { printf '%s' ''; return 0; }
  read -r -a items <<< "$raw"
  for item in "${items[@]}"; do
    case "$item" in
      awp) item=weapon_awp ;; negev) item=weapon_negev ;;
      m249) item=weapon_m249 ;; g3sg1) item=weapon_g3sg1 ;;
      scar-20|scar20) item=weapon_scar20 ;;
    esac
    if ! index="$(weapon_index "$item")"; then
      printf 'Invalid weapon name: %s\n' "$item" >&2; return 1;
    fi
    case "$seen_ids" in
      *",$index,"*) ;;
      *) result+="${result:+,}$item"; seen_ids+="$index," ;;
    esac
  done
  [[ ${#result} -le 1024 ]] || { echo 'Weapon list is too long' >&2; return 1; }
  printf '%s' "$result"
}

weapon_indices() {
  local list="$1" item indices=''
  local -a items=()
  [[ -z "$list" ]] && { printf '%s' ''; return 0; }
  IFS=, read -r -a items <<< "$list"
  for item in "${items[@]}"; do
    indices+="${indices:+,}$(weapon_index "$item")"
  done
  printf '%s' "$indices"
}

atomic_line() {
  local target="$1" content="$2" temp
  temp="$(mktemp "${target}.XXXXXX")"
  printf '%s\n' "$content" > "$temp"
  chmod 600 "$temp"
  mv -f "$temp" "$target"
}

ensure_hook() {
  local file="$1"
  [[ -f "$file" ]] || : > "$file"
  if ! grep -Fqx "$HOOK" "$file"; then
    printf '\n// CS2 Server Toolkit persistent settings\n%s\n' "$HOOK" >> "$file"
  fi
}

sync_config() {
  local list file
  mkdir -p "$CFG_DIR" "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  [[ -f "$STATE" ]] || atomic_line "$STATE" ''
  list="$(head -n 1 "$STATE")"
  [[ "$(normalize_weapons "$list")" == "$list" ]] || {
    echo 'Invalid persisted weapons list' >&2; return 1;
  }
  atomic_line "$GENERATED" "mp_items_prohibited \"$(weapon_indices "$list")\""
  ensure_hook "$CFG_DIR/cs2server.cfg"
  for file in \
    gamemode_competitive_server.cfg gamemode_casual_server.cfg \
    gamemode_competitive2v2_server.cfg gamemode_deathmatch_server.cfg \
    gamemode_retakecasual_server.cfg gamemode_armsrace_server.cfg; do
    ensure_hook "$CFG_DIR/$file"
  done
}

mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/.lock"
flock 9
case "${1:-}" in
  sync) sync_config ;;
  set)
    list="$(normalize_weapons "${2:-}")"
    atomic_line "$STATE" "$list"
    sync_config
    printf '%s\n' "$list"
    ;;
  show)
    [[ -f "$STATE" ]] && head -n 1 "$STATE" || true
    ;;
  ids)
    [[ -f "$STATE" ]] && weapon_indices "$(head -n 1 "$STATE")" || true
    ;;
  *) echo "Usage: $0 {sync|set LIST|show|ids}" >&2; exit 2 ;;
esac
