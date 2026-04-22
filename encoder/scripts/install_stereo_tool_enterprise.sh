#!/usr/bin/env bash
# Stereo Tool Enterprise installer wrapper for oMPX
set -euo pipefail

# This script wraps the legacy oMPX-Encoder-Debian-setup.sh logic for Stereo Tool Enterprise
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Download URL for Stereo Tool Enterprise
ST_ENTERPRISE_URL="https://download.thimeo.com/ST-Enterprise"
ST_ENTERPRISE_DIR="$HOME/stereo-tool-enterprise"
ST_ENTERPRISE_BIN="$ST_ENTERPRISE_DIR/stereo-tool-enterprise"

# Download if not present
if [ ! -f "$ST_ENTERPRISE_BIN" ]; then
  mkdir -p "$ST_ENTERPRISE_DIR"
  whiptail --title "Stereo Tool Enterprise" --msgbox "Downloading Stereo Tool Enterprise..." 8 60
  curl -L "$ST_ENTERPRISE_URL" -o "$ST_ENTERPRISE_BIN"
  chmod +x "$ST_ENTERPRISE_BIN"
  whiptail --title "Stereo Tool Enterprise" --msgbox "Stereo Tool Enterprise downloaded to $ST_ENTERPRISE_BIN" 8 60
fi

# Use a wrapper to ensure correct working directory for all relative paths
if [ -f "$SCRIPT_DIR/legacy-installer-wrapper.sh" ]; then
  bash "$SCRIPT_DIR/legacy-installer-wrapper.sh" install
else
  whiptail --title "Stereo Tool Enterprise" --msgbox "legacy-installer-wrapper.sh not found! Please add it to $SCRIPT_DIR." 10 60
  exit 1
fi
