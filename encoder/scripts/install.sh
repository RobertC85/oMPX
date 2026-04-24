#!/usr/bin/env bash
# oMPX interactive installer (regenerated)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# --- Ensure required dependencies are installed ---
install_dep() {
  PKG="$1"
  CMD="$2"
  if ! command -v "$CMD" >/dev/null 2>&1; then
    echo "[DEPENDENCY] $PKG not found. Installing..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update && sudo apt-get install -y "$PKG"
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y "$PKG"
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y "$PKG"
    elif command -v apk >/dev/null 2>&1; then
      sudo apk add "$PKG"
    else
      echo "[ERROR] Could not detect package manager. Please install $PKG manually."
      exit 1
    fi
  fi
}


# Ensure python3 and nginx are installed
install_dep "python3" "python3"
install_dep "nginx" "nginx"
install_dep "liquidsoap" "liquidsoap"
install_dep "ffmpeg" "ffmpeg"

# --- Idempotent nginx config update ---
NGINX_CONF_AVAILABLE="/etc/nginx/sites-available/ompx"
NGINX_CONF_ENABLED="/etc/nginx/sites-enabled/ompx"
NGINX_PORT=${OMPX_PUBLIC_PORT:-8082}
echo "[oMPX] Ensuring nginx is configured for port $NGINX_PORT..."
if [ -f /etc/nginx/sites-enabled/default ]; then
  sudo rm -f /etc/nginx/sites-enabled/default
  echo "[oMPX] Removed default nginx config."
fi
# Always ensure ompx-nginx.conf is present in sites-available and enabled
if [ -f "$SCRIPT_DIR/ompx-nginx.conf" ]; then
  sudo cp -f "$SCRIPT_DIR/ompx-nginx.conf" "$NGINX_CONF_AVAILABLE"
  echo "[oMPX] Copied ompx-nginx.conf to $NGINX_CONF_AVAILABLE."
  sudo ln -sf "$NGINX_CONF_AVAILABLE" "$NGINX_CONF_ENABLED"
  echo "[oMPX] Linked $NGINX_CONF_AVAILABLE to $NGINX_CONF_ENABLED."
  # Ensure listen directive is present and correct
  sudo sed -i -E "/listen /d" "$NGINX_CONF_AVAILABLE"
  sudo sed -i "/server_name _;/a \\    listen $NGINX_PORT;" "$NGINX_CONF_AVAILABLE"
  echo "[oMPX] Ensured listen $NGINX_PORT; in $NGINX_CONF_AVAILABLE."
  if sudo nginx -t; then
    sudo nginx -s reload || sudo service nginx restart
    echo "[oMPX] nginx reloaded and now listening on $NGINX_PORT."
  else
    echo "[oMPX] Config test failed! Please check $NGINX_CONF_ENABLED."
  fi
else
  echo "[oMPX] ompx-nginx.conf not found in $SCRIPT_DIR! Skipping nginx config."
fi
echo "[oMPX] Web UI should be available at: http://localhost:$NGINX_PORT (proxied to backend on 5000)"

# Optionally install X11, x11vnc, and chromium
if [ -t 0 ]; then
  echo "[OPTIONAL] Do you want to install X11 (xorg), x11vnc, and chromium for GUI/web kiosk support?"
  read -rp "Install X11 (xorg)? [y/N]: " X11_CHOICE
  if [[ "$X11_CHOICE" =~ ^[Yy]$ ]]; then
    install_dep "xorg" "Xorg"
  fi
  read -rp "Install x11vnc? [y/N]: " X11VNC_CHOICE
  if [[ "$X11VNC_CHOICE" =~ ^[Yy]$ ]]; then
    install_dep "x11vnc" "x11vnc"
  fi
  read -rp "Install chromium? [y/N]: " CHROMIUM_CHOICE
  if [[ "$CHROMIUM_CHOICE" =~ ^[Yy]$ ]]; then
    # Chromium package name varies by distro
    if command -v apt-get >/dev/null 2>&1; then
      install_dep "chromium-browser" "chromium-browser"
    elif command -v dnf >/dev/null 2>&1; then
      install_dep "chromium" "chromium"
    elif command -v yum >/dev/null 2>&1; then
      install_dep "chromium" "chromium"
    elif command -v apk >/dev/null 2>&1; then
      install_dep "chromium" "chromium"
    else
      echo "[WARN] Could not detect package manager for chromium. Please install manually if needed."
    fi
  fi
fi

# --- Vostok Radio Lite optional integration ---
VOSTOK_DIR="$SCRIPT_DIR/../../VostokRadioLite"
if [ ! -d "$VOSTOK_DIR" ] || [ -z "$(ls -A "$VOSTOK_DIR" 2>/dev/null)" ]; then
  echo "[NOTICE] Vostok Radio Lite is not an official part of oMPX."
  echo "[NOTICE] We invite Evan (the original developer) to collaborate with the oMPX project."
  read -rp "Would you like to clone Vostok Radio Lite as an optional processor and FM stack reference? [y/N]: " VOSTOK_CHOICE
  if [[ "$VOSTOK_CHOICE" =~ ^[Yy]$ ]]; then
    git clone https://github.com/radiopushka/VostokRadioLite "$VOSTOK_DIR"
    if [ $? -eq 0 ]; then
      echo "[INFO] Vostok Radio Lite cloned to $VOSTOK_DIR."
      echo "[INFO] You can use it as an optional processor or as a guide for your own FM stack."
    else
      echo "[ERROR] Failed to clone Vostok Radio Lite. Please check your network connection or clone manually."
    fi
  else
    echo "[INFO] Skipping Vostok Radio Lite integration."
  fi
else
  echo "[INFO] Vostok Radio Lite directory already present."
fi

# --- Whiptail detection and fallback logic ---
USE_WHIPTAIL=0
if command -v whiptail >/dev/null 2>&1; then
  USE_WHIPTAIL=1
else
  if [ -t 0 ]; then
    echo "Whiptail (menu interface) is not installed. How would you like to proceed?"
    echo "  1) Use text prompts (type your answers)"
    echo "  2) Install and use menu interface (whiptail)"
    read -rp "Enter 1 for text prompts, 2 to install whiptail [1]: " PROMPT_CHOICE
    PROMPT_CHOICE=${PROMPT_CHOICE:-1}
    if [ "$PROMPT_CHOICE" = "2" ]; then
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y whiptail && USE_WHIPTAIL=1
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y newt && USE_WHIPTAIL=1
      elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y newt && USE_WHIPTAIL=1
      elif command -v apk >/dev/null 2>&1; then
        sudo apk add newt && USE_WHIPTAIL=1
      else
        echo "[WARN] Could not detect package manager or install whiptail. Falling back to text prompts."
      fi
    fi
  fi
fi

SERVICES=(
  ompx-liquidsoap.service
  ompx-liquidsoap-preview.service
  ompx-web-ui.service
  mpx-mix.service
  mpx-processing-alsa.service
  mpx-source1.service
  mpx-source2.service
  mpx-stream-pull.service
  mpx-watchdog.service
)

SYSTEMD_DIR="/etc/systemd/system"
MISSING_SERVICES=()

# Step 1: Check for missing service files
for svc in "${SERVICES[@]}"; do
  if [ ! -f "$SYSTEMD_DIR/$svc" ]; then
    MISSING_SERVICES+=("$svc")
  fi
done

# Step 2: Generate missing service files if needed
if [ ${#MISSING_SERVICES[@]} -gt 0 ]; then
  MSG="The following required service files are missing:\n"
  for svc in "${MISSING_SERVICES[@]}"; do
    MSG+="- $svc\n"
  done
  MSG+="\nWould you like to generate them now?"
  if whiptail --title "Missing Services" --yesno "$MSG" 20 70; then
    for svc in "${MISSING_SERVICES[@]}"; do
      case "$svc" in
        ompx-liquidsoap.service)
          cat <<EOF | sudo tee "$SCRIPT_DIR/$svc" > /dev/null
[Unit]
Description=oMPX Liquidsoap Main Pipeline
After=network.target

[Service]
User=$OMPX_USER
Group=$OMPX_USER
ExecStart=/usr/bin/liquidsoap /opt/mpx-radio/ompx-processing.liq
Restart=on-failure
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
          ;;
        ompx-liquidsoap-preview.service)
          cat <<EOF | sudo tee "$SCRIPT_DIR/$svc" > /dev/null
[Unit]
Description=oMPX Liquidsoap Preview Pipeline
After=network.target

[Service]
User=$OMPX_USER
Group=$OMPX_USER
ExecStart=/usr/bin/liquidsoap /opt/mpx-radio/ompx-preview.liq
Restart=on-failure
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
          ;;
        ompx-web-ui.service)
          cat <<EOF | sudo tee "$SCRIPT_DIR/$svc" > /dev/null
[Unit]
Description=oMPX Web UI
After=network.target

[Service]
User=$OMPX_USER
Group=$OMPX_USER
ExecStart=/usr/bin/python3 /opt/mpx-radio/ompx-web-ui.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
          ;;
        mpx-mix.service)
          cat <<EOF | sudo tee "$SCRIPT_DIR/$svc" > /dev/null
[Unit]
Description=oMPX Mix Pipeline
After=network.target

[Service]
User=$OMPX_USER
Group=$OMPX_USER
ExecStart=/opt/mpx-radio/mpx-mix.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
          ;;
        mpx-processing-alsa.service)
          cat <<EOF | sudo tee "$SCRIPT_DIR/$svc" > /dev/null
[Unit]
Description=oMPX ALSA Processing Pipeline
After=network.target

[Service]
User=$OMPX_USER
Group=$OMPX_USER
ExecStart=/opt/mpx-radio/run_processing_alsa.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
          ;;
        mpx-source1.service)
          cat <<EOF | sudo tee "$SCRIPT_DIR/$svc" > /dev/null
[Unit]
Description=oMPX Source 1
After=network.target

[Service]
User=$OMPX_USER
Group=$OMPX_USER
ExecStart=/opt/mpx-radio/source1.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
          ;;
        mpx-source2.service)
          cat <<EOF | sudo tee "$SCRIPT_DIR/$svc" > /dev/null
[Unit]
Description=oMPX Source 2
After=network.target

[Service]
User=$OMPX_USER
Group=$OMPX_USER
ExecStart=/opt/mpx-radio/source2.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
          ;;
        mpx-stream-pull.service)
          cat <<EOF | sudo tee "$SCRIPT_DIR/$svc" > /dev/null
[Unit]
Description=oMPX Stream Pull
After=network.target

[Service]
User=$OMPX_USER
Group=$OMPX_USER
ExecStart=/opt/mpx-radio/mpx-stream-pull.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
          ;;
        mpx-watchdog.service)
          cat <<EOF | sudo tee "$SCRIPT_DIR/$svc" > /dev/null
[Unit]
Description=oMPX Watchdog
After=network.target

[Service]
User=$OMPX_USER
Group=$OMPX_USER
ExecStart=/opt/mpx-radio/mpx-watchdog.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
          ;;
        rds-sync-prog1.service)
          cat <<EOF | sudo tee "$SCRIPT_DIR/$svc" > /dev/null
[Unit]
Description=oMPX RDS Sync Program 1
After=network.target

[Service]
User=$OMPX_USER
Group=$OMPX_USER
ExecStart=/opt/mpx-radio/rds-sync-prog1.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
          ;;
        rds-sync-prog2.service)
          cat <<EOF | sudo tee "$SCRIPT_DIR/$svc" > /dev/null
[Unit]
Description=oMPX RDS Sync Program 2
After=network.target

[Service]
User=$OMPX_USER
Group=$OMPX_USER
ExecStart=/opt/mpx-radio/rds-sync-prog2.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
          ;;
        *)
          cat <<EOF | sudo tee "$SCRIPT_DIR/$svc" > /dev/null
[Unit]
Description=Placeholder for $svc
After=network.target

[Service]
ExecStart=/bin/true
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
          ;;
      esac
      sudo cp -v "$SCRIPT_DIR/$svc" "$SYSTEMD_DIR/" || true
      service_action enable "$svc"
      service_action start "$svc"
    done
    whiptail --title "oMPX Installer" --msgbox "Missing service files generated and enabled. You may edit them for your environment." 12 60
  else
    whiptail --title "oMPX Installer" --msgbox "Some services were not installed. Audio pipeline may be incomplete." 12 60
  fi
else
  whiptail --title "oMPX Installer" --msgbox "All required service files are present." 10 50
fi



# Step 3: Configure Icecast
whiptail --title "oMPX Installer" --msgbox "[DEBUG] About to run Icecast config script" 8 60
if whiptail --title "oMPX Installer" --yesno "Configure Icecast streaming settings now?" 10 50; then
  bash "$SCRIPT_DIR/configure_icecast.sh" || true
  whiptail --title "oMPX Installer" --msgbox "[DEBUG] Returned from Icecast config script" 8 60
  whiptail --title "oMPX Installer" --msgbox "Icecast configuration complete." 10 50
else
  whiptail --title "oMPX Installer" --msgbox "Icecast configuration skipped." 10 50
fi

# Step 4: Prompt for Program 1 and 2 stream URLs
DEFAULTS_VAR="/workspaces/oMPX/defaults.var"

# Load defaults, but guard against unset variables
if [ -f "$DEFAULTS_VAR" ]; then
  source "$DEFAULTS_VAR"
fi
PROGRAM1_SOURCE="${PROGRAM1_SOURCE:-http://127.0.0.1:8000/stream1}"
PROGRAM2_SOURCE="${PROGRAM2_SOURCE:-http://127.0.0.1:8000/stream2}"

PROMPT1="Enter Program 1 audio source URL (leave blank for default: $PROGRAM1_SOURCE):"
PROMPT2="Enter Program 2 audio source URL (leave blank for default: $PROGRAM2_SOURCE):"

USER_PROGRAM1_SOURCE=$(whiptail --title "Audio Source" --inputbox "$PROMPT1" 10 70 3>&1 1>&2 2>&3)
if [ -z "$USER_PROGRAM1_SOURCE" ]; then
  USER_PROGRAM1_SOURCE="$PROGRAM1_SOURCE"
fi

USER_PROGRAM2_SOURCE=$(whiptail --title "Audio Source" --inputbox "$PROMPT2" 10 70 3>&1 1>&2 2>&3)
if [ -z "$USER_PROGRAM2_SOURCE" ]; then
  USER_PROGRAM2_SOURCE="$PROGRAM2_SOURCE"
fi

# Save new values to defaults.var for future installs
cat > "$DEFAULTS_VAR" <<EOF
# oMPX Default Source Variables
# This file is sourced by the installer if the user leaves a prompt blank.
# Edit these values to set default audio sources for unattended or repeatable installs.

# Program 1 audio source (Icecast URL, ALSA device, file, etc.)
PROGRAM1_SOURCE="$USER_PROGRAM1_SOURCE"
# Program 2 audio source
PROGRAM2_SOURCE="$USER_PROGRAM2_SOURCE"
# Add more defaults as needed
EOF

whiptail --title "Audio Sources Saved" --msgbox "Audio source URLs saved to $DEFAULTS_VAR:\n\nProgram 1: $USER_PROGRAM1_SOURCE\nProgram 2: $USER_PROGRAM2_SOURCE" 12 70

whiptail --title "oMPX Installer" --msgbox "[DEBUG] About to run ALSA config script" 8 60
# Step 5: Configure ALSA audio
if whiptail --title "oMPX Installer" --yesno "Configure ALSA audio settings now?" 10 50; then
  bash "$SCRIPT_DIR/configure_alsa.sh" || true
  whiptail --title "oMPX Installer" --msgbox "ALSA configuration complete." 10 50
else
  whiptail --title "oMPX Installer" --msgbox "ALSA configuration skipped." 10 50
fi


# Step 5: Select and install audio processor (now includes Vostok)
PROCESSOR=$(whiptail --title "Audio Processor" --menu "Select which audio processor to use:" 20 60 4 \
  "ompx" "oMPX (default, open source)" \
  "vostok" "VostokRadioLite (C, FM/MPX+RDS)" \
  "stereotool" "Stereo Tool Enterprise (proprietary)" \
  "masterme" "MasterMe (coming soon)" 3>&1 1>&2 2>&3)

case "$PROCESSOR" in
  vostok)
    whiptail --title "VostokRadioLite" --msgbox "VostokRadioLite selected. Building and installing as a service..." 10 60
    (cd "$VOSTOK_DIR" && make)
    # Create systemd service for VostokRadioLite
    cat <<EOF | sudo tee /etc/systemd/system/vostokradio.service > /dev/null
[Unit]
Description=VostokRadioLite FM/MPX+RDS Processor
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$VOSTOK_DIR
ExecStart=$VOSTOK_DIR/vtkradio --stdio < /dev/zero > /dev/null
Restart=on-failure
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable vostokradio.service
    sudo systemctl restart vostokradio.service
    whiptail --title "VostokRadioLite" --msgbox "VostokRadioLite service installed and started." 10 60
    ;;
  stereotool)
    whiptail --title "Stereo Tool Enterprise" --msgbox "Stereo Tool Enterprise selected. Proceeding with download and install..." 10 60
    if [ -f "$SCRIPT_DIR/install_stereo_tool_enterprise.sh" ]; then
      bash "$SCRIPT_DIR/install_stereo_tool_enterprise.sh"
    else
      whiptail --title "Stereo Tool Enterprise" --msgbox "Installer script not found! Please add install_stereo_tool_enterprise.sh to $SCRIPT_DIR." 10 60
    fi
    ;;
  masterme)
    MASTERME_WEB_PORT=$(whiptail --title "MasterMe Web UI" --inputbox "Enter port for MasterMe web interface (default: 8082):" 10 60 8082 3>&1 1>&2 2>&3)
    if [ -z "$MASTERME_WEB_PORT" ]; then
      MASTERME_WEB_PORT=8082
    fi
    whiptail --title "MasterMe" --msgbox "MasterMe selected. Proceeding with install...\nWeb interface will run on port $MASTERME_WEB_PORT." 10 60
    if [ -f "$SCRIPT_DIR/install_masterme.sh" ]; then
      MASTERME_WEB_PORT="$MASTERME_WEB_PORT" bash "$SCRIPT_DIR/install_masterme.sh"
    else
      whiptail --title "MasterMe" --msgbox "Installer script not found! Please add install_masterme.sh to $SCRIPT_DIR." 10 60
    fi
    ;;
  ompx|*)
    OMPX_BACKEND_PORT=$(whiptail --title "oMPX Backend Port" --inputbox "Enter port for oMPX backend (default: 5000):" 10 60 5000 3>&1 1>&2 2>&3)
    if [ -z "$OMPX_BACKEND_PORT" ]; then
      OMPX_BACKEND_PORT=5000
    fi
    OMPX_PUBLIC_PORT=$(whiptail --title "oMPX Public Port" --inputbox "Enter public port for oMPX web interface (default: 8082):" 10 60 8082 3>&1 1>&2 2>&3)
    if [ -z "$OMPX_PUBLIC_PORT" ]; then
      OMPX_PUBLIC_PORT=8082
    fi
    whiptail --title "oMPX Processor" --msgbox "Using oMPX built-in processor (default).\nWeb interface backend will run on port $OMPX_BACKEND_PORT and be proxied to public port $OMPX_PUBLIC_PORT." 10 60
    if [ -f "$SCRIPT_DIR/../ompx-web-ui.service" ]; then
      sudo sed -i "s/Environment=OMPX_WEB_PORT=.*/Environment=OMPX_WEB_PORT=$OMPX_BACKEND_PORT/" "$SCRIPT_DIR/../ompx-web-ui.service"
    fi
    if [ -f "$SCRIPT_DIR/../ompx-nginx.conf" ]; then
      sudo sed -i "s/listen [0-9]\+/listen $OMPX_PUBLIC_PORT/" "$SCRIPT_DIR/../ompx-nginx.conf"
      sudo sed -i "s|proxy_pass http://127.0.0.1:[0-9]\+/|proxy_pass http://127.0.0.1:$OMPX_BACKEND_PORT/|" "$SCRIPT_DIR/../ompx-nginx.conf"
    fi
    # Create/enable systemd service for Python backend
    if [ -f "$SCRIPT_DIR/../ompx-web-ui.service" ]; then
      sudo cp "$SCRIPT_DIR/../ompx-web-ui.service" /etc/systemd/system/
      sudo systemctl daemon-reload
      sudo systemctl enable ompx-web-ui.service
      sudo systemctl restart ompx-web-ui.service
    fi
    # Create/enable systemd service for Liquidsoap
    if [ -f "$SCRIPT_DIR/../ompx-liquidsoap.service" ]; then
      sudo cp "$SCRIPT_DIR/../ompx-liquidsoap.service" /etc/systemd/system/
      sudo systemctl enable ompx-liquidsoap.service
      sudo systemctl restart ompx-liquidsoap.service
    fi
    # Create/enable systemd service for FFmpeg (example)
    cat <<EOF | sudo tee /etc/systemd/system/ompx-ffmpeg.service > /dev/null
[Unit]
Description=oMPX FFmpeg Service (example)
After=network.target

[Service]
User=$USER
Group=$USER
ExecStart=/usr/bin/ffmpeg -version
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable ompx-ffmpeg.service
    sudo systemctl restart ompx-ffmpeg.service
    # --- Copy all web UI files to /var/www/html ---
    WEBUI_SRC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    sudo mkdir -p /var/www/html
    sudo cp -v "$WEBUI_SRC_DIR"/index.html "$WEBUI_SRC_DIR"/program1.html "$WEBUI_SRC_DIR"/program2.html "$WEBUI_SRC_DIR"/main.js "$WEBUI_SRC_DIR"/legacy.html "$WEBUI_SRC_DIR"/modern.html "$WEBUI_SRC_DIR"/preloader.css "$WEBUI_SRC_DIR"/404.html /var/www/html/ || true
    echo "[INSTALL] index.html and all web UI files copied to /var/www/html."
    if command -v nginx >/dev/null 2>&1; then
      if pgrep nginx >/dev/null 2>&1; then
        echo "[INSTALL] Reloading nginx to apply new web UI files..."
        sudo nginx -s reload || echo "[WARNING] nginx reload failed. Please reload manually if needed."
      else
        echo "[INFO] nginx is not running; skipping reload."
      fi
    fi
    echo "[INSTALL] Web UI files copied to /var/www/html."
    if command -v nginx >/dev/null 2>&1; then
      echo "[INSTALL] Reloading nginx to apply new web UI files..."
      sudo nginx -s reload || echo "[WARNING] nginx reload failed. Please reload manually if needed."
    fi
    ;;
esac


# --- Idempotent service (re)enable/restart and user-friendly summary ---
if [ -f "$SCRIPT_DIR/ompx-web-ui.service" ]; then
  sudo cp "$SCRIPT_DIR/ompx-web-ui.service" /etc/systemd/system/
  echo "[service] ompx-web-ui.service updated."
fi
if [ -f "$SCRIPT_DIR/nginx.service" ]; then
  sudo cp "$SCRIPT_DIR/nginx.service" /etc/systemd/system/
  echo "[service] nginx.service updated."
fi

if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
  sudo systemctl daemon-reload
  sudo systemctl enable ompx-web-ui.service
  sudo systemctl restart ompx-web-ui.service
  sudo systemctl enable nginx.service
  sudo systemctl restart nginx.service
  INIT_MSG="All services enabled and running via systemd."
elif command -v service >/dev/null 2>&1; then
  sudo service nginx restart || true
  INIT_MSG="nginx restarted with 'service'. Please run: python3 /workspaces/oMPX/encoder/ompx-web-ui.py &"
else
  INIT_MSG="No supported init system detected. Please start services manually:"
  INIT_MSG="$INIT_MSG\n  python3 /workspaces/oMPX/encoder/ompx-web-ui.py &"
  INIT_MSG="$INIT_MSG\n  nginx -c /workspaces/oMPX/encoder/ompx-nginx.conf"
fi

echo "[oMPX] Install/update complete!"
echo "[oMPX] Web UI backend: http://localhost:5000"
echo "[oMPX] Web UI (via nginx proxy): http://localhost:$NGINX_PORT"
echo "[oMPX] $INIT_MSG"

whiptail --title "oMPX Installer" --msgbox "oMPX install/update complete!\n\nWeb UI backend: http://localhost:5000\nWeb UI (nginx proxy): http://localhost:$NGINX_PORT\n\n$INIT_MSG" 14 70
