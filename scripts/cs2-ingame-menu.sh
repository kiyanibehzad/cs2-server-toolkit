#!/usr/bin/env bash
set -euo pipefail

CS2_HOME="${CS2_HOME:-$HOME}"
CS2_DIR="${CS2_DIR:-$CS2_HOME/cs2-ds}"
GAME_DIR="$CS2_DIR/game/csgo"
ADDONS="$GAME_DIR/addons"
CONFIG_TOOL="$CS2_DIR/cs2-ingame-config.py"
ADMIN_FILE="$ADDONS/counterstrikesharp/configs/admins.json"
GAMEINFO="$GAME_DIR/gameinfo.gi"
MARKER="$CS2_DIR/toolkit-config/ingame-menu.enabled"
PLUGIN_SOURCE="$CS2_DIR/toolkit-assets/Cs2ToolkitMenu.dll"
PLUGIN_DEPS="$CS2_DIR/toolkit-assets/Cs2ToolkitMenu.deps.json"
PLUGIN_DIR="$ADDONS/counterstrikesharp/plugins/Cs2ToolkitMenu"
SERVICE_NAME="${SERVICE_NAME:-cs2-ds}"

# Pinned official upstream builds. Update these together after checking game compatibility.
METAMOD_VERSION=2.0.0.1472
METAMOD_URL="https://github.com/alliedmodders/metamod-source/releases/download/$METAMOD_VERSION/mmsource-2.0.0-git1472-linux.tar.gz"
METAMOD_SHA256=a4c7e962d4f704e55a91a560f1db024bd75ff38cdc2543a704a1151cda551fa6
CSS_VERSION=1.0.375
CSS_URL="https://github.com/roflmuffin/CounterStrikeSharp/releases/download/v$CSS_VERSION/counterstrikesharp-with-runtime-linux-$CSS_VERSION.zip"
CSS_SHA256=26f9259ec7b584cb0afb464652423e88f9841ed3a675ba6db4871af07406947f

die() { printf '[ingame-menu] %s\n' "$*" >&2; exit 1; }
info() { printf '[ingame-menu] %s\n' "$*"; }
need_base() {
  [[ "$(id -u)" -ne 0 ]] || die 'Run as the non-root game user.'
  [[ -x "$CONFIG_TOOL" ]] || die "Missing $CONFIG_TOOL; reinstall the toolkit first."
  [[ -f "$GAMEINFO" ]] || die "Missing $GAMEINFO"
}
validate_id() {
  [[ "$1" =~ ^7656119[0-9]{10}$ ]] || die 'Enter a 17-digit SteamID64 beginning with 7656119.'
}
reload_admins() {
  if systemctl --user is-active --quiet "$SERVICE_NAME"; then
    "$CS2_DIR/cs2-admin.sh" rcon css_admins_reload >/dev/null || info 'Admin file saved; reload with a server restart.'
  fi
}
repair_loader() {
  [[ -f "$MARKER" ]] || return 0
  [[ -f "$ADDONS/metamod/bin/linuxsteamrt64/metamod.2.cs2.so" ]] || die 'Metamod is missing; use install to repair it.'
  python3 "$CONFIG_TOOL" repair-loader "$GAMEINFO"
}
verify_running() {
  local attempt meta plugins
  for ((attempt=1; attempt<=30; attempt++)); do
    meta="$("$CS2_DIR/cs2-admin.sh" rcon 'meta list' 2>/dev/null || true)"
    plugins="$("$CS2_DIR/cs2-admin.sh" rcon 'css_plugins list' 2>/dev/null || true)"
    if [[ "$meta" == *CounterStrikeSharp* && "$plugins" == *'CS2 Server Toolkit Menu'* && "$plugins" == *LOADED* ]]; then
      info 'Metamod, CounterStrikeSharp, and the toolkit plugin are loaded.'
      return 0
    fi
    sleep 2
  done
  die 'Plugin files were installed, but live loading was not verified. Check cs2-ds service logs.'
}
install_menu() {
  local first_admin="${1:-}" label="${2:-}" was_active=0
  need_base
  [[ -f "$PLUGIN_SOURCE" && -f "$PLUGIN_DEPS" ]] || die 'Compiled toolkit plugin is missing; reinstall the toolkit first.'
  [[ -z "$first_admin" ]] || validate_id "$first_admin"
  if [[ -z "$first_admin" && ! -s "$ADMIN_FILE" ]]; then
    die 'A SteamID64 is required for the first admin.'
  fi
  if [[ -z "$first_admin" && -z "$(python3 "$CONFIG_TOOL" admin-list "$ADMIN_FILE")" ]]; then
    die 'No toolkit admin exists. Provide a SteamID64 to install.'
  fi
  command -v curl >/dev/null || die 'curl is required.'
  command -v unzip >/dev/null || die 'unzip is required.'
  command -v sha256sum >/dev/null || die 'sha256sum is required.'
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' EXIT
  info 'Downloading verified upstream packages before restarting the server.'
  curl -fL --retry 2 --connect-timeout 15 "$METAMOD_URL" -o "$stage/metamod.tar.gz"
  curl -fL --retry 2 --connect-timeout 15 "$CSS_URL" -o "$stage/css.zip"
  printf '%s  %s\n' "$METAMOD_SHA256" "$stage/metamod.tar.gz" | sha256sum -c - >/dev/null || die 'Metamod checksum mismatch.'
  printf '%s  %s\n' "$CSS_SHA256" "$stage/css.zip" | sha256sum -c - >/dev/null || die 'CounterStrikeSharp checksum mismatch.'
  mkdir -p "$stage/metamod" "$stage/css" "$ADDONS" "$PLUGIN_DIR" "$(dirname "$MARKER")"
  tar -xzf "$stage/metamod.tar.gz" -C "$stage/metamod"
  unzip -oq "$stage/css.zip" -d "$stage/css"
  [[ -f "$stage/metamod/addons/metamod/bin/linuxsteamrt64/metamod.2.cs2.so" ]] || die 'Metamod archive layout changed.'
  [[ -f "$stage/css/addons/counterstrikesharp/api/CounterStrikeSharp.API.dll" ]] || die 'CounterStrikeSharp archive layout changed.'
  systemctl --user is-active --quiet "$SERVICE_NAME" && was_active=1
  if [[ -f "$ADDONS/metamod/metaplugins.ini" ]]; then
    cp -p "$ADDONS/metamod/metaplugins.ini" "$stage/metaplugins.ini"
  fi
  cp -a "$stage/metamod/addons/." "$ADDONS/"
  cp -a "$stage/css/addons/." "$ADDONS/"
  if [[ -f "$stage/metaplugins.ini" ]]; then
    cp -p "$stage/metaplugins.ini" "$ADDONS/metamod/metaplugins.ini"
  fi
  install -m 0644 "$PLUGIN_SOURCE" "$PLUGIN_DIR/Cs2ToolkitMenu.dll"
  install -m 0644 "$PLUGIN_DEPS" "$PLUGIN_DIR/Cs2ToolkitMenu.deps.json"
  printf 'metamod=%s\ncounterstrikesharp=%s\n' "$METAMOD_VERSION" "$CSS_VERSION" > "$MARKER"
  repair_loader
  if [[ -n "$first_admin" ]]; then
    python3 "$CONFIG_TOOL" admin-add "$ADMIN_FILE" "$first_admin" "${label:-Toolkit-$first_admin}"
  fi
  if ((was_active)); then
    if ! systemctl --user restart "$SERVICE_NAME"; then
      systemctl --user start "$SERVICE_NAME" || true
      die 'Server restart failed. Inspect cs2-ds service logs.'
    fi
    verify_running
  else
    info 'Server was stopped. Plugin will load on its next start.'
  fi
  info 'In game, an authorized admin can enter !toolkit or !admin.'
}
status_menu() {
  if [[ -f "$MARKER" ]]; then
    info "Installed: $(tr '\n' ' ' < "$MARKER")"
    python3 "$CONFIG_TOOL" admin-list "$ADMIN_FILE"
    if systemctl --user is-active --quiet "$SERVICE_NAME"; then
      "$CS2_DIR/cs2-admin.sh" rcon 'meta list' || true
      "$CS2_DIR/cs2-admin.sh" rcon 'css_plugins list' || true
    fi
  else
    info 'Not installed.'
  fi
}

command="${1:-status}"
shift || true
case "$command" in
  install) install_menu "${1:-}" "${2:-}" ;;
  status) status_menu ;;
  repair-loader) repair_loader ;;
  add-admin)
    need_base
    validate_id "${1:-}"
    python3 "$CONFIG_TOOL" admin-add "$ADMIN_FILE" "$1" "${2:-Toolkit-$1}"
    reload_admins
    info "Admin added: $1"
    ;;
  remove-admin)
    need_base
    validate_id "${1:-}"
    python3 "$CONFIG_TOOL" admin-remove "$ADMIN_FILE" "$1"
    reload_admins
    info "Admin removed: $1"
    ;;
  list-admins) python3 "$CONFIG_TOOL" admin-list "$ADMIN_FILE" ;;
  *) die 'Usage: cs2-ingame-menu.sh {install [SteamID64 [name]]|status|repair-loader|add-admin SteamID64 [name]|remove-admin SteamID64|list-admins}' ;;
esac
