#!/bin/bash
# CS2 Web Panel Manager script
# Manages the web admin panel service and outputs status and connection info.

set -uo pipefail

CS2_USER="${CS2_USER:-$(id -un)}"
CS2_HOME="${CS2_HOME:-/home/$CS2_USER}"
CS2_DIR="${CS2_DIR:-$CS2_HOME/cs2-ds}"
CONF="$CS2_DIR/.update.env"
[[ -f "$CONF" ]] && . "$CONF"

HOST_IP="${HOST_IP:-127.0.0.1}"
WEB_PORT="${WEB_PORT:-3000}"
WEB_USER="${WEB_ADMIN_USER:-admin}"
WEB_PASS="${WEB_ADMIN_PASS:-${RCON_PASS:-ChangeMe123!}}"
SERVICE_NAME="cs2-web"

# Colors
green="\033[32m"
red="\033[31m"
yellow="\033[33m"
cyan="\033[36m"
bold="\033[1m"
reset="\033[0m"

action="${1:-info}"

check_status() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || echo "inactive"
  else
    if pgrep -f "node.*web/server.js" >/dev/null 2>&1; then
      echo "active"
    else
      echo "inactive"
    fi
  fi
}

case "$action" in
  start)
    echo -e "${cyan}[i] Starting $SERVICE_NAME...${reset}"
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user start "$SERVICE_NAME"
    else
      cd "$CS2_DIR/web" && nohup node server.js >/dev/null 2>&1 &
    fi
    sleep 1
    echo -e "${green}[OK] Status: $(check_status)${reset}"
    ;;
  stop)
    echo -e "${yellow}[!] Stopping $SERVICE_NAME...${reset}"
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user stop "$SERVICE_NAME"
    else
      pkill -f "node.*web/server.js" || true
    fi
    sleep 1
    echo -e "${green}[OK] Status: $(check_status)${reset}"
    ;;
  restart)
    echo -e "${cyan}[i] Restarting $SERVICE_NAME...${reset}"
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user restart "$SERVICE_NAME"
    else
      pkill -f "node.*web/server.js" || true
      sleep 1
      cd "$CS2_DIR/web" && nohup node server.js >/dev/null 2>&1 &
    fi
    sleep 1
    echo -e "${green}[OK] Status: $(check_status)${reset}"
    ;;
  logs)
    if command -v journalctl >/dev/null 2>&1; then
      journalctl --user -u "$SERVICE_NAME" -f -n 50
    else
      echo -e "${yellow}[!] journalctl is not available on this system.${reset}"
    fi
    ;;
  status|info|*)
    CURRENT_STATUS="$(check_status)"
    echo -e "${bold}==============================================${reset}"
    echo -e "${bold}🌐 CS2 Web Admin Panel Details${reset}"
    echo -e "${bold}==============================================${reset}"
    if [[ "$CURRENT_STATUS" == "active" ]]; then
      echo -e " Status   : ${green}${bold}● ACTIVE (Running)${reset}"
    else
      echo -e " Status   : ${red}${bold}○ INACTIVE (Stopped)${reset}"
    fi
    echo -e " URL      : ${cyan}${bold}http://${HOST_IP}:${WEB_PORT}${reset}"
    echo -e " Username : ${bold}${WEB_USER}${reset}"
    echo -e " Password : ${yellow}(Set in ${CONF})${reset}"
    echo -e " Port     : ${bold}${WEB_PORT}${reset}"
    echo -e " Service  : ${bold}${SERVICE_NAME}.service${reset}"
    echo -e "${bold}==============================================${reset}"
    echo -e " Commands: $0 {start|stop|restart|logs|status}"
    ;;
esac
