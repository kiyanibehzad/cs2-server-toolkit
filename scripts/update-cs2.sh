#!/usr/bin/env bash
set -euo pipefail

# Compatibility entry point for servers that used ~/update-cs2.sh manually.
# A forced check still waits for an empty server and uses the same lock as timers.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/cs2-safe-update.sh" --force
