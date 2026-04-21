#!/usr/bin/env bash
# oMPX uninstall logic
set -euo pipefail

echo "[UNINSTALL] oMPX uninstall logic placeholder"
DIR="$(dirname "$0")"
source "$DIR/common.sh"

echo "[UNINSTALL] Stopping and disabling oMPX services..."
for svc in ompx-web-ui.service ompx-liquidsoap.service ompx-liquidsoap-preview.service; do
	service_action stop "$svc"
	service_action disable "$svc"
	sudo rm -f "$SYSTEMD_DIR/$svc"
done
service_action daemon-reload ompx-liquidsoap.service

echo "[UNINSTALL] Removing oMPX files and user..."
sudo rm -rf "$SYS_SCRIPTS_DIR" "$OMPX_LOG_DIR"
sudo userdel -r "$OMPX_USER" 2>/dev/null || true
echo "[UNINSTALL] Uninstall complete."
