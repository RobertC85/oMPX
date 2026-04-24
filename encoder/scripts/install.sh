#!/usr/bin/env bash
# oMPX interactive installer (regenerated)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

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
  rds-sync-prog1.service
  rds-sync-prog2.service
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
if [ -f "$DEFAULTS_VAR" ]; then
  source "$DEFAULTS_VAR"
fi

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

# Step 5: Select and install audio processor
PROCESSOR=$(whiptail --title "Audio Processor" --menu "Select which audio processor to use:" 15 60 3 \
  "ompx" "oMPX (default, open source)" \
  "stereotool" "Stereo Tool Enterprise (proprietary)" \
  "masterme" "MasterMe (coming soon)" 3>&1 1>&2 2>&3)


case "$PROCESSOR" in
  stereotool)
    whiptail --title "Stereo Tool Enterprise" --msgbox "Stereo Tool Enterprise selected. Proceeding with download and install..." 10 60
    if [ -f "$SCRIPT_DIR/install_stereo_tool_enterprise.sh" ]; then
      bash "$SCRIPT_DIR/install_stereo_tool_enterprise.sh"
    else
      whiptail --title "Stereo Tool Enterprise" --msgbox "Installer script not found! Please add install_stereo_tool_enterprise.sh to $SCRIPT_DIR." 10 60
    fi
    ;;
  masterme)
    # Prompt for web interface port
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
    # Prompt for backend and public ports
    OMPX_BACKEND_PORT=$(whiptail --title "oMPX Backend Port" --inputbox "Enter port for oMPX backend (default: 5000):" 10 60 5000 3>&1 1>&2 2>&3)
    if [ -z "$OMPX_BACKEND_PORT" ]; then
      OMPX_BACKEND_PORT=5000
    fi
    OMPX_PUBLIC_PORT=$(whiptail --title "oMPX Public Port" --inputbox "Enter public port for oMPX web interface (default: 8082):" 10 60 8082 3>&1 1>&2 2>&3)
    if [ -z "$OMPX_PUBLIC_PORT" ]; then
      OMPX_PUBLIC_PORT=8082
    fi
    whiptail --title "oMPX Processor" --msgbox "Using oMPX built-in processor (default).\nWeb interface backend will run on port $OMPX_BACKEND_PORT and be proxied to public port $OMPX_PUBLIC_PORT." 10 60
    # Update systemd service file for backend port
    if [ -f "$SCRIPT_DIR/../ompx-web-ui.service" ]; then
      sudo sed -i "s/Environment=OMPX_WEB_PORT=.*/Environment=OMPX_WEB_PORT=$OMPX_BACKEND_PORT/" "$SCRIPT_DIR/../ompx-web-ui.service"
    fi
    # Update nginx config for proxy port
    if [ -f "$SCRIPT_DIR/../ompx-nginx.conf" ]; then
      sudo sed -i "s/listen [0-9]\+/listen $OMPX_PUBLIC_PORT/" "$SCRIPT_DIR/../ompx-nginx.conf"
      sudo sed -i "s|proxy_pass http://127.0.0.1:[0-9]\+/|proxy_pass http://127.0.0.1:$OMPX_BACKEND_PORT/|" "$SCRIPT_DIR/../ompx-nginx.conf"
    fi
    if command -v python3 >/dev/null 2>&1; then
      nohup env OMPX_WEB_PORT=$OMPX_BACKEND_PORT python3 "$SCRIPT_DIR/ompx_profiles_api.py" &
      sleep 2
      # Remove nohup.out for commit safety
      rm -f nohup.out
      whiptail --title "oMPX Web UI" --msgbox "oMPX Profile Editor started on port $OMPX_BACKEND_PORT (proxied to $OMPX_PUBLIC_PORT).\nOpen http://localhost:$OMPX_PUBLIC_PORT in your browser." 10 70
    else
      whiptail --title "oMPX Web UI" --msgbox "Python3 not found. Cannot start oMPX Profile Editor." 8 60
    fi
    # --- Copy all web UI files to /var/www/html ---
    WEBUI_SRC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    sudo mkdir -p /var/www/html
    sudo cp -v "$WEBUI_SRC_DIR"/index.html "$WEBUI_SRC_DIR"/program1.html "$WEBUI_SRC_DIR"/program2.html "$WEBUI_SRC_DIR"/main.js "$WEBUI_SRC_DIR"/legacy.html "$WEBUI_SRC_DIR"/modern.html "$WEBUI_SRC_DIR"/preloader.css "$WEBUI_SRC_DIR"/404.html /var/www/html/ || true
    echo "[INSTALL] index.html and all web UI files copied to /var/www/html."
    # Force nginx reload to ensure new files are served
    if command -v nginx >/dev/null 2>&1; then
      # Only reload nginx if it is running
      if pgrep nginx >/dev/null 2>&1; then
        echo "[INSTALL] Reloading nginx to apply new web UI files..."
        sudo nginx -s reload || echo "[WARNING] nginx reload failed. Please reload manually if needed."
      else
        echo "[INFO] nginx is not running; skipping reload."
      fi
    fi
    # Copy any additional static files as needed
    echo "[INSTALL] Web UI files copied to /var/www/html."
    # --- Reload nginx to serve new files ---
    if command -v nginx >/dev/null 2>&1; then
      echo "[INSTALL] Reloading nginx to apply new web UI files..."
      sudo nginx -s reload || echo "[WARNING] nginx reload failed. Please reload manually if needed."
    fi
    ;;
esac

whiptail --title "oMPX Installer" --msgbox "oMPX install complete!" 10 50
