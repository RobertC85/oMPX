
#!/usr/bin/env bash
# oMPX Icecast configuration logic
set -euo pipefail
set -x

echo "[ICECAST] Icecast config logic placeholder"
DIR="$(dirname "$0")"
source "$DIR/common.sh"

PROFILE="$OMPX_HOME/.profile"
echo "[ICECAST] Configuring Icecast connection..."

if command -v whiptail >/dev/null 2>&1; then
  echo "[DEBUG] About to prompt for ICECAST_HOST (whiptail)"
  ICECAST_HOST=$(whiptail --title "Icecast Config" --inputbox "Enter Icecast host/IP:" 10 60 "127.0.0.1" 3>&1 1>&2 2>&3)
  echo "[DEBUG] Got ICECAST_HOST: $ICECAST_HOST"
  ICECAST_PORT=$(whiptail --title "Icecast Config" --inputbox "Enter Icecast port:" 10 60 "8000" 3>&1 1>&2 2>&3)
  echo "[DEBUG] Got ICECAST_PORT: $ICECAST_PORT"
  ICECAST_SOURCE_USER=$(whiptail --title "Icecast Config" --inputbox "Enter Icecast source username:" 10 60 "source" 3>&1 1>&2 2>&3)
  echo "[DEBUG] Got ICECAST_SOURCE_USER: $ICECAST_SOURCE_USER"
  ICECAST_PASSWORD=$(whiptail --title "Icecast Config" --inputbox "Enter Icecast source password (leave blank to auto-generate):" 10 60 "" 3>&1 1>&2 2>&3)
  echo "[DEBUG] Got ICECAST_PASSWORD: $ICECAST_PASSWORD"
  if [ -z "$ICECAST_PASSWORD" ]; then
    ICECAST_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    whiptail --title "Icecast Config" --msgbox "No password entered. Generated password: $ICECAST_PASSWORD" 10 60
  fi
  ICECAST_MOUNT=$(whiptail --title "Icecast Config" --inputbox "Enter Icecast mountpoint:" 10 60 "/mpx" 3>&1 1>&2 2>&3)
  echo "[DEBUG] Got ICECAST_MOUNT: $ICECAST_MOUNT"
else
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
fi


# --- Ensure /etc/icecast2/icecast.xml exists and is configured ---
ICECAST_ETC_DIR="/etc/icecast2"
ICECAST_XML="$ICECAST_ETC_DIR/icecast.xml"
ICECAST_TEMPLATE="/workspaces/oMPX/encoder/icecast.xml.example"

sudo mkdir -p "$ICECAST_ETC_DIR"
if [ ! -f "$ICECAST_XML" ]; then
  echo "[ICECAST] No icecast.xml found, copying template..."
  sudo cp "$ICECAST_TEMPLATE" "$ICECAST_XML"
fi


# Set Icecast to run as the ompx user (not root)
sudo sed -i "/<changeowner>/,/<\/changeowner>/d" "$ICECAST_XML"
sudo sed -i "/<fileserve>1<\/fileserve>/a \\n  <changeowner>\n    <user>$OMPX_USER</user>\n    <group>$OMPX_USER</group>\n  </changeowner>" "$ICECAST_XML"

# Update config with user values (simple sed replace)
sudo sed -i "s|<source-password>.*</source-password>|<source-password>$ICECAST_PASSWORD</source-password>|" "$ICECAST_XML"
sudo sed -i "s|<admin-password>.*</admin-password>|<admin-password>$ICECAST_PASSWORD</admin-password>|" "$ICECAST_XML"
sudo sed -i "s|<relay-password>.*</relay-password>|<relay-password>$ICECAST_PASSWORD</relay-password>|" "$ICECAST_XML"
sudo sed -i "s|<port>.*</port>|<port>$ICECAST_PORT</port>|" "$ICECAST_XML"
sudo sed -i "s|<hostname>.*</hostname>|<hostname>$ICECAST_HOST</hostname>|" "$ICECAST_XML"

echo "ICECAST_HOST=\"$ICECAST_HOST\"" > "$PROFILE"
echo "ICECAST_PORT=\"$ICECAST_PORT\"" >> "$PROFILE"
echo "ICECAST_SOURCE_USER=\"$ICECAST_SOURCE_USER\"" >> "$PROFILE"
echo "ICECAST_PASSWORD=\"$ICECAST_PASSWORD\"" >> "$PROFILE"
echo "ICECAST_MOUNT=\"$ICECAST_MOUNT\"" >> "$PROFILE"

whiptail --title "Icecast Config" --msgbox "Icecast config file created/updated at $ICECAST_XML.\nYou may need to start Icecast manually:\n\nicecast2 -c $ICECAST_XML" 12 70
sudo chown "$OMPX_USER:$OMPX_USER" "$PROFILE" && sudo chmod 644 "$PROFILE"
echo "[ICECAST] Icecast settings saved to $PROFILE."
echo "[DEBUG] configure_icecast.sh completed successfully."
