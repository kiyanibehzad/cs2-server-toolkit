#!/usr/bin/env bash
set -euo pipefail

CS2_HOME="${CS2_HOME:-$HOME}"
CS2_DIR="$CS2_HOME/cs2-ds"
PLUGIN_DIR="$CS2_DIR/game/csgo/addons/counterstrikesharp/plugins/Cs2ToolkitMenuV2"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_DIR="$REPO_DIR/plugins/Cs2ToolkitMenuV2/dist"
SERVICE_NAME="${SERVICE_NAME:-cs2-ds}"

die() { printf '[ingame-menu-v2] %s\n' "$*" >&2; exit 1; }
info() { printf '[ingame-menu-v2] %s\n' "$*"; }

case "${1:-status}" in
  install-local-test)
    [[ "$(id -u)" -ne 0 ]] || die 'Run as the non-root game user.'
    [[ -f "$CS2_DIR/game/csgo/addons/counterstrikesharp/api/CounterStrikeSharp.API.dll" ]] || die 'Install the original in-game menu first (CounterStrikeSharp is required).'
    [[ -f "$ASSET_DIR/Cs2ToolkitMenuV2.dll" && -f "$ASSET_DIR/Cs2ToolkitMenuV2.deps.json" ]] || die 'V2 plugin assets are missing from the repository.'
    mkdir -p "$PLUGIN_DIR"
    install -m 0644 "$ASSET_DIR/Cs2ToolkitMenuV2.dll" "$PLUGIN_DIR/Cs2ToolkitMenuV2.dll"
    install -m 0644 "$ASSET_DIR/Cs2ToolkitMenuV2.deps.json" "$PLUGIN_DIR/Cs2ToolkitMenuV2.deps.json"
    if systemctl --user is-active --quiet "$SERVICE_NAME"; then
      systemctl --user restart "$SERVICE_NAME"
      loaded=0
      for ((attempt=1; attempt<=30; attempt++)); do
        plugins="$("$CS2_DIR/cs2-admin.sh" rcon 'css_plugins list' 2>/dev/null || true)"
        if printf '%s\n' "$plugins" | grep -E 'CS2 Server Toolkit Menu V2 Beta.*LOADED|LOADED.*CS2 Server Toolkit Menu V2 Beta' >/dev/null; then loaded=1; break; fi
        sleep 2
      done
      ((loaded)) || die 'Plugin copied but live loading was not verified. Check service logs.'
    fi
    info 'V2 plugin installed. The tester must also compile and install the client layout using hud/build.ps1 -InstallLocal.'
    info 'Open with !adminv2 (or bind F6 css_adminv2 in the client console).'
    ;;
  status)
    if [[ -f "$PLUGIN_DIR/Cs2ToolkitMenuV2.dll" ]]; then
      info 'V2 beta plugin installed.'
      if systemctl --user is-active --quiet "$SERVICE_NAME"; then
        "$CS2_DIR/cs2-admin.sh" rcon 'css_plugins list' || true
      fi
    else
      info 'V2 beta plugin not installed.'
    fi
    ;;
  remove)
    [[ "$(id -u)" -ne 0 ]] || die 'Run as the non-root game user.'
    [[ -f "$PLUGIN_DIR/Cs2ToolkitMenuV2.dll" ]] || die 'V2 beta plugin is not installed.'
    rm -f "$PLUGIN_DIR/Cs2ToolkitMenuV2.dll" "$PLUGIN_DIR/Cs2ToolkitMenuV2.deps.json"
    rmdir "$PLUGIN_DIR" 2>/dev/null || true
    if systemctl --user is-active --quiet "$SERVICE_NAME"; then systemctl --user restart "$SERVICE_NAME"; fi
    info 'V2 beta plugin removed.'
    ;;
  *) die 'Usage: cs2-ingame-menu-v2.sh {install-local-test|status|remove}' ;;
esac
