
#!/usr/bin/env bash
# oMPX Icecast configuration logic
set -euo pipefail
set -x

echo "[ICECAST] Icecast config logic placeholder"
DIR="$(dirname "$0")"
source "$DIR/common.sh"

PROFILE="$OMPX_HOME/.profile"
echo "[ICECAST] Configuring Icecast connection..."
echo "[DEBUG] About to prompt for ICECAST_HOST"
read -p "Enter Icecast host/IP [127.0.0.1]: " ICECAST_HOST
echo "[DEBUG] Got ICECAST_HOST: $ICECAST_HOST"
ICECAST_HOST="${ICECAST_HOST:-127.0.0.1}"
echo "[DEBUG] About to prompt for ICECAST_PORT"
read -p "Enter Icecast port [8000]: " ICECAST_PORT
echo "[DEBUG] Got ICECAST_PORT: $ICECAST_PORT"
ICECAST_PORT="${ICECAST_PORT:-8000}"
echo "[DEBUG] About to prompt for ICECAST_SOURCE_USER"
read -p "Enter Icecast source username [source]: " ICECAST_SOURCE_USER
echo "[DEBUG] Got ICECAST_SOURCE_USER: $ICECAST_SOURCE_USER"
ICECAST_SOURCE_USER="${ICECAST_SOURCE_USER:-source}"
echo "[DEBUG] About to prompt for ICECAST_PASSWORD"
read -p "Enter Icecast source password (leave blank to auto-generate): " ICECAST_PASSWORD
echo "[DEBUG] Got ICECAST_PASSWORD: $ICECAST_PASSWORD"
if [ -z "$ICECAST_PASSWORD" ]; then
  ICECAST_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
  echo "[ICECAST] No password entered. Generated password: $ICECAST_PASSWORD"
fi
echo "[DEBUG] About to prompt for ICECAST_MOUNT"
read -p "Enter Icecast mountpoint [/mpx]: " ICECAST_MOUNT
echo "[DEBUG] Got ICECAST_MOUNT: $ICECAST_MOUNT"
ICECAST_MOUNT="${ICECAST_MOUNT:-/mpx}"

echo "ICECAST_HOST=\"$ICECAST_HOST\"" > "$PROFILE"
echo "ICECAST_PORT=\"$ICECAST_PORT\"" >> "$PROFILE"
echo "ICECAST_SOURCE_USER=\"$ICECAST_SOURCE_USER\"" >> "$PROFILE"
echo "ICECAST_PASSWORD=\"$ICECAST_PASSWORD\"" >> "$PROFILE"
echo "ICECAST_MOUNT=\"$ICECAST_MOUNT\"" >> "$PROFILE"
sudo chown "$OMPX_USER:$OMPX_USER" "$PROFILE" && sudo chmod 644 "$PROFILE"
echo "[ICECAST] Icecast settings saved to $PROFILE."
echo "[DEBUG] configure_icecast.sh completed successfully."
