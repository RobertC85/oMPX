#!/usr/bin/env bash
# oMPX update logic
set -euo pipefail

echo "[UPDATE] oMPX update logic placeholder"
DIR="$(dirname "$0")"
source "$DIR/common.sh"

echo "[UPDATE] Updating oMPX files..."
# Example: update web UI and scripts
sudo cp -v ../ompx-web-ui.py "$SYS_SCRIPTS_DIR/" || true
# Restart services
for svc in ompx-web-ui.service ompx-liquidsoap.service ompx-liquidsoap-preview.service; do
	service_action restart "$svc"
done
echo "[UPDATE] Update complete."
