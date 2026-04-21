#!/usr/bin/env bash
# oMPX ALSA configuration logic
set -euo pipefail

echo "[ALSA] ALSA config logic placeholder"
DIR="$(dirname "$0")"
source "$DIR/common.sh"

echo "[ALSA] Configuring ALSA..."
read -p "Enter ALSA card name [default]: " ALSA_CARD
ALSA_CARD="${ALSA_CARD:-default}"
read -p "Enter ALSA device number [0]: " ALSA_DEVICE
ALSA_DEVICE="${ALSA_DEVICE:-0}"

echo "pcm.!default {\n  type hw\n  card $ALSA_CARD\n  device $ALSA_DEVICE\n}" | sudo tee "$ASOUND_CONF_PATH" > /dev/null
echo "[ALSA] ALSA settings saved to $ASOUND_CONF_PATH."
