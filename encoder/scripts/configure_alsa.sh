#!/usr/bin/env bash
# oMPX ALSA configuration logic
set -euo pipefail

echo "[ALSA] ALSA config logic placeholder"
DIR="$(dirname "$0")"
source "$DIR/common.sh"

echo "[ALSA] Configuring ALSA..."

if command -v whiptail >/dev/null 2>&1; then
  ALSA_CARD=$(whiptail --title "ALSA Config" --inputbox "Enter ALSA card name:" 10 60 "default" 3>&1 1>&2 2>&3)
  ALSA_DEVICE=$(whiptail --title "ALSA Config" --inputbox "Enter ALSA device number:" 10 60 "0" 3>&1 1>&2 2>&3)
else
  read -p "Enter ALSA card name [default]: " ALSA_CARD
  ALSA_CARD="${ALSA_CARD:-default}"
  read -p "Enter ALSA device number [0]: " ALSA_DEVICE
  ALSA_DEVICE="${ALSA_DEVICE:-0}"
fi

echo -e "pcm.!default {\n  type hw\n  card $ALSA_CARD\n  device $ALSA_DEVICE\n}" | sudo tee "$ASOUND_CONF_PATH" > /dev/null
echo "[ALSA] ALSA settings saved to $ASOUND_CONF_PATH."
