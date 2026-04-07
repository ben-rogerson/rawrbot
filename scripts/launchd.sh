#!/bin/bash
# Install or uninstall launchd agents for RawrBot scheduled tasks.
# Usage: ./scripts/launchd.sh install | uninstall | status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_DIR="${SCRIPT_DIR}/../launchd"
TARGET_DIR="${HOME}/Library/LaunchAgents"

AGENTS=(
  com.rawrbot.task-tick
  com.rawrbot.plan-tick
  com.rawrbot.validate-tick
)

install_agent() {
  local agent="$1"
  local src="$2"
  local dst="${TARGET_DIR}/${agent}.plist"
  if [ ! -f "$src" ]; then
    echo "SKIP  ${agent} (plist not found)"
    return
  fi
  launchctl bootout "gui/$(id -u)/${agent}" 2>/dev/null || true
  ln -sf "$src" "$dst"
  launchctl bootstrap "gui/$(id -u)" "$dst"
  echo "OK    ${agent}"
}

install() {
  mkdir -p "${TARGET_DIR}"
  for agent in "${AGENTS[@]}"; do
    install_agent "$agent" "${PLIST_DIR}/${agent}.plist"
  done
  echo ""
  echo "All agents installed. Run '$0 status' to verify."
}

uninstall() {
  for agent in "${AGENTS[@]}"; do
    dst="${TARGET_DIR}/${agent}.plist"
    launchctl bootout "gui/$(id -u)/${agent}" 2>/dev/null || true
    rm -f "$dst"
    echo "OK    ${agent} removed"
  done
  echo ""
  echo "All agents uninstalled."
}

status() {
  for agent in "${AGENTS[@]}"; do
    if launchctl print "gui/$(id -u)/${agent}" &>/dev/null; then
      echo "LOADED   ${agent}"
    else
      echo "NOT LOADED  ${agent}"
    fi
  done
}

case "${1:-}" in
  install)   install ;;
  uninstall) uninstall ;;
  status)    status ;;
  *)
    echo "Usage: $0 install | uninstall | status"
    exit 1
    ;;
esac
