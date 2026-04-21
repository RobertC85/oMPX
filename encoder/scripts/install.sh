#!/usr/bin/env bash
# oMPX install logic
set -euo pipefail

echo "[DEBUG] install.sh started."
echo "[INSTALL] oMPX install logic placeholder"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

echo "[INSTALL] Installing oMPX dependencies..."
sudo apt-get update
sudo apt-get install -y liquidsoap nginx icecast2 ffmpeg whiptail

# Create user if missing
if ! id -u "$OMPX_USER" >/dev/null 2>&1; then
	sudo useradd -m -s "$OMPX_SHELL" "$OMPX_USER"
fi
sudo mkdir -p "$OMPX_LOG_DIR"
sudo chown "$OMPX_USER:$OMPX_USER" "$OMPX_LOG_DIR"

# Deploy scripts and services (minimal example)
sudo mkdir -p "$SYS_SCRIPTS_DIR"
sudo cp -v "$SCRIPT_DIR/ompx-web-ui.py" "$SYS_SCRIPTS_DIR/" || true

# Enable/start services
for svc in ompx-web-ui.service ompx-liquidsoap.service ompx-liquidsoap-preview.service; do
	sudo cp -v "$SCRIPT_DIR/$svc" "$SYSTEMD_DIR/" || true
	service_action enable "$svc"
	service_action start "$svc"
done

echo "[INSTALL] oMPX install complete."
