# --- Prompt helper: respects AUTO_MODE, INTERACTIVE_MODE, and NO_MENU ---
prompt_helper() {
  # Usage: prompt_helper VAR_NAME "Prompt text" [default] [timeout]
  #   VAR_NAME: variable to set
  #   Prompt text: prompt to display
  #   default: default value if user presses enter or times out
  #   timeout: seconds to wait (ignored in AUTO_MODE or INTERACTIVE_MODE)
  local __var_name="$1"
  local __prompt="$2"
  local __default="${3-}"
  local __timeout="${4-60}"
  local __input=""
  if [ "$AUTO_MODE" = true ]; then
    __input="$__default"
    echo "$__prompt $__input (auto)"
  elif [ "$INTERACTIVE_MODE" = true ] && [ "$NO_MENU" = false ] && command -v whiptail >/dev/null 2>&1; then
    # Use whiptail inputbox for all prompts in interactive mode unless --no-menu
    __input=$(whiptail --inputbox "$__prompt" 10 70 "$__default" 3>&1 1>&2 2>&3)
    if [ -z "$__input" ] && [ -n "$__default" ]; then
      __input="$__default"
    fi
  elif [ "$INTERACTIVE_MODE" = true ]; then
    # Fallback to plain read if whiptail not available or --no-menu
    read -p "$__prompt" __input
    if [ -z "$__input" ] && [ -n "$__default" ]; then
      __input="$__default"
    fi

  # Default: force INTERACTIVE_MODE unless --auto or --no-interactive is specified
  AUTO_MODE=false
  INTERACTIVE_MODE=false
  NO_MENU=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --auto)
        AUTO_MODE=true
        INTERACTIVE_MODE=false
        ;;
      --no-interactive)
        INTERACTIVE_MODE=false
        AUTO_MODE=true
        ;;
      --interactive)
        INTERACTIVE_MODE=true
        AUTO_MODE=false
        ;;
      --no-menu)
        NO_MENU=true
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      --version|-v)
        show_version
        exit 0
        ;;
      *)
        # Accumulate positional args
        POSITIONAL_ARGS+=("$1")
        ;;
    esac
    shift
  done

  # Force INTERACTIVE_MODE by default unless explicitly overridden
  if [ "$AUTO_MODE" = false ] && [ "$INTERACTIVE_MODE" = false ]; then
    INTERACTIVE_MODE=true
  fi
  sudo ./oMPX-Encoder-Debian-setup.sh --menu    # Launch interactive menu (if whiptail is installed)

EOF
    exit 0
  fi
done
# --- Robust flag parsing: allow combining --auto, --interactive, --help, --version ---
# --- Flag variables ---
INTERACTIVE_MODE=false
AUTO_MODE=false
NO_MENU=false
SHOW_HELP=false
SHOW_VERSION=false
PARSED_ARGS=()
for arg in "$@"; do
  case "$arg" in
    -v|--version)
      SHOW_VERSION=true
      ;;
    -h|--help)
      SHOW_HELP=true
      ;;
    --interactive)
      INTERACTIVE_MODE=true
      ;;
    --auto)
      AUTO_MODE=true
      ;;
    --no-menu)
      NO_MENU=true
      ;;
    *)
      PARSED_ARGS+=("$arg")
      ;;
  esac
done
# Show help/version and exit if requested
if [ "$SHOW_VERSION" = true ]; then
  echo "oMPX Installer version: $OMPX_VERSION"
  exit 0
fi
if [ "$SHOW_HELP" = true ]; then
  cat <<EOF
oMPX-Encoder-Debian-setup.sh – oMPX Installer v$OMPX_VERSION

Usage: sudo ./oMPX-Encoder-Debian-setup.sh [OPTIONS]

Options:
  -h, --help         Show this help message and exit
  -v, --version      Show installer version and exit
  --update           Only update files that are newer (preserves user settings)
  --force-update     Overwrite all managed files (default)
  --nuke             Uninstall oMPX and remove all files/services
  --menu             Launch interactive whiptail menu (if available)
  --interactive      Require explicit answers for all prompts (no timeouts, no defaults)
  --auto             Automated mode: assume all defaults, never prompt

Procedure:
  1. Installs all required dependencies (Liquidsoap, Nginx, etc.)
  2. Deploys/updates oMPX Web UI and backend
  3. Overwrites all managed files by default (unless --update is used)
  4. Sets up and restarts all oMPX systemd services
  5. Web UI is served on port 8082 by default

Examples:
  sudo ./oMPX-Encoder-Debian-setup.sh           # Full install/overwrite (recommended)
  sudo ./oMPX-Encoder-Debian-setup.sh --update  # Only update newer files, preserve settings
  sudo ./oMPX-Encoder-Debian-setup.sh --nuke    # Uninstall oMPX completely
  sudo ./oMPX-Encoder-Debian-setup.sh --menu    # Launch interactive menu (if whiptail is installed)
  sudo ./oMPX-Encoder-Debian-setup.sh --auto    # Fully automated, no prompts
EOF
  exit 0
fi
# Replace positional args with parsed ones (removes --auto/--interactive/--help/--version)
set -- "${PARSED_ARGS[@]}"


echo "[oMPX Installer] Running: $0"
echo "[oMPX Installer] Version: $OMPX_VERSION"

# --- Install required dependencies ---
echo "Installing required dependencies (including Liquidsoap)..."
sudo apt-get update
sudo apt-get install -y liquidsoap

# --- oMPX Web UI manual start helper script ---
cat > /usr/local/bin/start-ompx-web-ui.sh <<'EOF'
#!/bin/bash
# Start oMPX Web UI backend manually and log output

LOGFILE="/var/log/ompx-web-ui.log"
PYTHON_SCRIPT="/opt/mpx-radio/ompx-web-ui.py"

# Stop any running instance
sudo pkill -f "$PYTHON_SCRIPT"

# Start the backend in the background with nohup
sudo nohup python3 "$PYTHON_SCRIPT" > "$LOGFILE" 2>&1 &

echo "oMPX Web UI backend started. Logs: $LOGFILE"
EOF
chmod +x /usr/local/bin/start-ompx-web-ui.sh
# --- End oMPX Web UI manual start helper script ---

# --- Ensure critical variables are defined early for all code paths (including uninstall) ---
OMPX_USER="ompx"
OMPX_HOME="/home/ompx"
OMPX_LOG_DIR="${OMPX_HOME}/logs"
OMPX_SHELL="/bin/bash"
SYS_SCRIPTS_DIR="/opt/mpx-radio"
FIFOS_DIR="${SYS_SCRIPTS_DIR}/fifos"
SYSTEMD_DIR="/etc/systemd/system"
STEREO_TOOL_WRAPPER="/usr/local/bin/stereo-tool"
STEREO_TOOL_ENTERPRISE_BIN="${OMPX_HOME}/stereo-tool-enterprise/stereo-tool-enterprise"
STEREO_TOOL_ENTERPRISE_LAUNCHER="/usr/local/bin/stereo-tool-enterprise-launch"
STEREO_TOOL_ENTERPRISE_SERVICE="${SYSTEMD_DIR}/stereo-tool-enterprise.service"
OMPX_STREAM_PULL_SERVICE="${SYSTEMD_DIR}/mpx-stream-pull.service"
OMPX_SOURCE1_SERVICE="${SYSTEMD_DIR}/mpx-source1.service"
OMPX_SOURCE2_SERVICE="${SYSTEMD_DIR}/mpx-source2.service"
RDS_SYNC_PROG1_SERVICE="${SYSTEMD_DIR}/rds-sync-prog1.service"
RDS_SYNC_PROG2_SERVICE="${SYSTEMD_DIR}/rds-sync-prog2.service"
OMPX_WEB_UI_SERVICE="${SYSTEMD_DIR}/ompx-web-ui.service"
OMPX_WEB_KIOSK_SERVICE="${SYSTEMD_DIR}/ompx-web-kiosk.service"
OMPX_ADD="/usr/local/bin/ompx_add_source"
ASOUND_CONF_PATH="/etc/asound.conf"
OMPX_AUDIO_UDEV_RULE="/etc/udev/rules.d/70-ompx-audio.rules"
ASOUND_MAP_HELPER="/usr/local/bin/asound-map"
ASOUND_SWITCH_HELPER="/usr/local/bin/asound-switch"
SAMPLE_RATE=192000
NON_MPX_SAMPLE_RATE="${NON_MPX_SAMPLE_RATE:-48000}"
CRON_SLEEP=10

# --- Liquidsoap preview service ---
cat > /usr/local/bin/ompx-liquidsoap-preview.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LIQ_SCRIPT="/workspaces/oMPX/encoder/ompx-preview.liq"
liquidsoap "$LIQ_SCRIPT"
EOF
chmod +x /usr/local/bin/ompx-liquidsoap-preview.sh

cat > /etc/systemd/system/ompx-liquidsoap-preview.service <<'EOF'
[Unit]
Description=oMPX Liquidsoap Preview Processing
After=network.target

[Service]
Type=simple
User=ompx
ExecStart=/usr/local/bin/ompx-liquidsoap-preview.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/ompx-liquidsoap-preview.service
systemctl daemon-reload || true
# Preview service is started/stopped by backend on demand
# --- Liquidsoap processing service ---
cat > /usr/local/bin/ompx-liquidsoap.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LIQ_SCRIPT="/workspaces/oMPX/encoder/ompx-processing.liq"
liquidsoap "$LIQ_SCRIPT"
EOF
chmod +x /usr/local/bin/ompx-liquidsoap.sh

cat > /etc/systemd/system/ompx-liquidsoap.service <<'EOF'
[Unit]
Description=oMPX Liquidsoap Processing
After=network.target

[Service]
Type=simple
User=ompx
ExecStart=/usr/local/bin/ompx-liquidsoap.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/ompx-liquidsoap.service
systemctl daemon-reload || true
systemctl enable --now ompx-liquidsoap.service || true

# --- Update Icecast streaming to use Liquidsoap output ---
cat > /usr/local/bin/ompx-icecast-mpx.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ICECAST_HOST="${ICECAST_HOST:-127.0.0.1}"
ICECAST_PORT="${ICECAST_PORT:-8000}"
ICECAST_SOURCE_USER="${ICECAST_SOURCE_USER:-source}"
ICECAST_PASSWORD="${ICECAST_PASSWORD:-}"
ICECAST_MOUNT="${ICECAST_MOUNT:-/mpx}"
ICECAST_SAMPLE_RATE="${ICECAST_SAMPLE_RATE:-192000}"
ICECAST_BIT_DEPTH="${ICECAST_BIT_DEPTH:-16}"
ICECAST_CODEC="flac"
# Ensure ompx-processing.liq is present and up to date
src_liq=""
UPDATE_ONLY=false
# --- Help flag: print usage and exit ---
for arg in "$@"; do
  if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
    cat <<EOF
oMPX-Encoder-Debian-setup.sh – oMPX Installer v$OMPX_VERSION

Usage: sudo ./oMPX-Encoder-Debian-setup.sh [OPTIONS]

Options:
  -h, --help         Show this help message and exit
  --update           Only update files that are newer (preserves user settings)
  --force-update     Overwrite all managed files (default)
  --nuke             Uninstall oMPX and remove all files/services
  --menu             Launch interactive whiptail menu (if available)

Procedure:
  1. Installs all required dependencies (Liquidsoap, Nginx, etc.)
  2. Deploys/updates oMPX Web UI and backend
  3. Overwrites all managed files by default (unless --update is used)
  4. Sets up and restarts all oMPX systemd services
  5. Web UI is served on port 8082 by default

Examples:
  sudo ./oMPX-Encoder-Debian-setup.sh           # Full install/overwrite (recommended)
  sudo ./oMPX-Encoder-Debian-setup.sh --update  # Only update newer files, preserve settings
  sudo ./oMPX-Encoder-Debian-setup.sh --nuke    # Uninstall oMPX completely
  sudo ./oMPX-Encoder-Debian-setup.sh --menu    # Launch interactive menu (if whiptail is installed)

EOF
    exit 0
  fi
done
for arg in "$@"; do
  if [ "$arg" = "--update" ]; then
    UPDATE_ONLY=true
  fi
done
if [ -f /root/ompx/encoder/ompx-processing.liq ]; then
  src_liq="/root/ompx/encoder/ompx-processing.liq"
fi
if [ -f "$(pwd)/ompx-processing.liq" ]; then
  if [ -z "$src_liq" ] || [ "$(pwd)/ompx-processing.liq" -nt "$src_liq" ]; then
    src_liq="$(pwd)/ompx-processing.liq"
  fi
fi
if [ -n "$src_liq" ]; then
  if [ "${UPDATE_ONLY:-false}" = true ]; then
    if [ ! -f /workspaces/oMPX/encoder/ompx-processing.liq ] || [ "$src_liq" -nt /workspaces/oMPX/encoder/ompx-processing.liq ]; then
      cp -f "$src_liq" /workspaces/oMPX/encoder/ompx-processing.liq
      echo "[INFO] (update) Copied ompx-processing.liq from $src_liq to /workspaces/oMPX/encoder/."
    fi
  else
    cp -f "$src_liq" /workspaces/oMPX/encoder/ompx-processing.liq
    echo "[INFO] (overwrite) Copied ompx-processing.liq from $src_liq to /workspaces/oMPX/encoder/."
  fi
fi
LIQ_PORT=1234

# Wait for Liquidsoap to be ready
while ! nc -z 127.0.0.1 $LIQ_PORT; do sleep 1; done

liquidsoap --telnet 127.0.0.1:$LIQ_PORT "help" >/dev/null 2>&1 || true

liquidsoap --telnet 127.0.0.1:$LIQ_PORT "help" >/dev/null 2>&1 || true

exec ffmpeg -hide_banner -loglevel warning -f s16le -ar "$ICECAST_SAMPLE_RATE" -ac 2 -i - \
## Removed hardcoded overwrite of index.html to preserve latest committed UI
      --card: Canvas;
      --accent: Highlight;
      --ink: CanvasText;
      --muted: GrayText;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: Canvas;
        --card: Canvas;
        --accent: Highlight;
        --ink: CanvasText;
        --muted: GrayText;
      }
    }

    body {
      background: var(--bg);
      font-family: system-ui, sans-serif;
  <!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>oMPX Live Control</title>
  <style>
  :root { --bg:#0f1b1a; --card:#132825; --accent:#f2b642; --ink:#f4f7f5; --muted:#9fb8b0; }
  body { margin:0; font-family: ui-sans-serif, sans-serif; background: radial-gradient(circle at 10% 10%, #1c3b35, var(--bg)); color:var(--ink); }
  -f flac "icecast://$ICECAST_SOURCE_USER:$ICECAST_PASSWORD@$ICECAST_HOST:$ICECAST_PORT$ICECAST_MOUNT"
EOF
chmod +x /usr/local/bin/ompx-icecast-mpx.sh

cat > /etc/systemd/system/ompx-icecast-mpx.service <<'EOF'
[Unit]
Description=oMPX MPX to Icecast (from Liquidsoap)
After=ompx-liquidsoap.service

[Service]
Type=simple
User=ompx
ExecStart=/usr/local/bin/ompx-icecast-mpx.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/ompx-icecast-mpx.service
systemctl daemon-reload || true
systemctl enable --now ompx-icecast-mpx.service || true
#!/usr/bin/env bash
set -euo pipefail
# oMPX unified installer + ALSA asound.conf setup (192kHz sample rate, 80kHz subcarrier frequency)
# Requires: Debian/Ubuntu or bare metal with standard kernel (not Proxmox PVE, and yes we know Proxmox is based on Debian, but their custom kernel often lacks snd_aloop which is critical for this setup)
# For best results, use a standard Debian kernel (linux-image-amd64) that includes snd_aloop
# Date: 2026-04-07

 # --- Default to whiptail menu unless --nuke or --prompt is specified ---
if ! command -v whiptail >/dev/null 2>&1; then
  echo "[INFO] whiptail not found. Installing..."
  apt-get update && apt-get install -y whiptail
fi
whiptail --title "oMPX Installer v$OMPX_VERSION" --msgbox "oMPX Installer\nVersion: $OMPX_VERSION" 8 50
CHOICE=$(whiptail --title "oMPX Installer v$OMPX_VERSION" --menu "Choose an action (oMPX $OMPX_VERSION)" 20 70 10 \
  "install" "Install/Update oMPX" \
  "reinstall" "Reinstall (clean/fresh)" \
  "uninstall" "Uninstall (remove all)" \
  "update" "Update oMPX (git pull + restart)" \
  "abort" "Abort/Exit" \
  3>&1 1>&2 2>&3)
case "$CHOICE" in
  install)
    echo "[INFO] Proceeding with install/update (oMPX version $OMPX_VERSION)..."
    ;;
  reinstall)
    echo "[INFO] Proceeding with reinstall (oMPX version $OMPX_VERSION)..."
    set -- "$@" --force-reinstall
    ;;
  uninstall)
    echo "[INFO] Proceeding with uninstall (--nuke, oMPX version $OMPX_VERSION)..."
    "$0" --nuke
    exit $?
    ;;
  update)
    whiptail --title "oMPX Updater" --msgbox "Updating oMPX from git and restarting installer..." 8 50
    cd "$(dirname \"$0\")/.." || cd ..
    git pull
    exec "$0" "$@"
    ;;
  abort|*)
    echo "[INFO] Aborted by user."
    exit 0
    ;;
esac

# --- Command-line argument parsing for --nuke and --menu ---
if [[ "$*" == *--nuke* ]]; then
  echo "[INFO] --nuke switch detected: performing full uninstall (no prompts)"
  # Uninstall logic (copied from 'U' case in main prompt)
  echo "[INFO] Stopping systemd services..."
  systemctl stop mpx-processing-alsa.service mpx-watchdog.service mpx-stream-pull.service mpx-source1.service mpx-source2.service rds-sync-prog1.service rds-sync-prog2.service 2>/dev/null || true
  systemctl stop stereo-tool-enterprise.service ompx-web-ui.service ompx-web-kiosk.service 2>/dev/null || true
  echo "[INFO] Disabling systemd services..."
  systemctl disable mpx-processing-alsa.service mpx-watchdog.service mpx-stream-pull.service mpx-source1.service mpx-source2.service rds-sync-prog1.service rds-sync-prog2.service 2>/dev/null || true
  systemctl disable stereo-tool-enterprise.service ompx-web-ui.service ompx-web-kiosk.service 2>/dev/null || true
  rm -f "${SYSTEMD_DIR}/mpx-processing-alsa.service" "${SYSTEMD_DIR}/mpx-watchdog.service" "${OMPX_STREAM_PULL_SERVICE}" "${OMPX_SOURCE1_SERVICE}" "${OMPX_SOURCE2_SERVICE}" "${RDS_SYNC_PROG1_SERVICE}" "${RDS_SYNC_PROG2_SERVICE}" "${STEREO_TOOL_ENTERPRISE_SERVICE}" "${OMPX_WEB_UI_SERVICE}" "${OMPX_WEB_KIOSK_SERVICE}" "${STEREO_TOOL_ENTERPRISE_LAUNCHER}" "${SYS_SCRIPTS_DIR}/ompx-web-ui.py" "${SYS_SCRIPTS_DIR}/ompx-web-kiosk.sh"
  systemctl daemon-reload || true
  echo "[INFO] Removing cron jobs..."
  if command -v crontab >/dev/null 2>&1 && id -u "${OMPX_USER}" >/dev/null 2>&1; then
    crontab -u "${OMPX_USER}" -l 2>/dev/null | grep -v "${SYS_SCRIPTS_DIR}/source" | sed '/^$/d' | crontab -u "${OMPX_USER}" - 2>/dev/null || true
  else
    echo "[WARNING] crontab command not found; skipping cron cleanup"
  fi
  echo "[INFO] Removing files and directories..."
  rm -f "${STEREO_TOOL_WRAPPER}" "${STEREO_TOOL_WRAPPER}.real-check" "${OMPX_ADD}"
  rm -rf "${SYS_SCRIPTS_DIR}" "${OMPX_LOG_DIR}" /var/log/radio-opus1.log /var/log/radio-opus2.log /var/log/radio-source1.log /var/log/radio-source2.log
  rm -f "${OMPX_AUDIO_UDEV_RULE}" || true
  rm -f "${OMPX_HOME}/.profile" "${OMPX_HOME}/.profile".bak.* || true
  echo "[INFO] Removing oMPX user..."
  if id -u "${OMPX_USER}" >/dev/null 2>&1; then userdel -r "${OMPX_USER}" || true; fi
  echo "[INFO] Unloading snd_aloop module..."
  modprobe -r snd_aloop 2>/dev/null || true
  echo "[SUCCESS] Uninstall complete. (--nuke)"
  exit 0
fi

if [[ "$*" == *--menu* ]]; then
  if ! command -v whiptail >/dev/null 2>&1; then
    echo "[ERROR] whiptail is not installed. Please install it (apt install whiptail) or run without --menu."
    exit 1
  fi
  CHOICE=$(whiptail --title "oMPX Installer Menu" --menu "Choose an action" 20 70 10 \
    "install" "Install/Update oMPX" \
    "reinstall" "Reinstall (clean/fresh)" \
    "uninstall" "Uninstall (remove all)" \
    "abort" "Abort/Exit" \
    3>&1 1>&2 2>&3)
  case "$CHOICE" in
    install)
      echo "[INFO] Proceeding with install/update..."
      ;;
    reinstall)
      set -- "$@" --force-reinstall
      ;;
    uninstall)
      echo "[INFO] Proceeding with uninstall (--nuke)..."
      "$0" --nuke
      exit $?
      ;;
    abort|*)
      echo "[INFO] Aborted by user."
      exit 0
      ;;
  esac
fi

echo "[$(date +'%F %T')] oMPX installer starting..."
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${INSTALLER_DIR}/.." && pwd)"
# --- Configurable variables ---
ENV_RADIO1_SET="${RADIO1_URL+x}"
ENV_RADIO1_VAL="${RADIO1_URL-}"
ENV_RADIO2_SET="${RADIO2_URL+x}"
ENV_RADIO2_VAL="${RADIO2_URL-}"
ENV_STREAM_ENGINE_SET="${STREAM_ENGINE+x}"
ENV_STREAM_ENGINE_VAL="${STREAM_ENGINE-}"
ENV_STREAM_SILENCE_SET="${STREAM_SILENCE_MAX_DBFS+x}"
ENV_STREAM_SILENCE_VAL="${STREAM_SILENCE_MAX_DBFS-}"
ENV_ENABLE_DSCA_SET="${ENABLE_DSCA_SINKS+x}"
ENV_ENABLE_DSCA_VAL="${ENABLE_DSCA_SINKS-}"
ENV_ENABLE_PREVIEW_SET="${ENABLE_PREVIEW_SINKS+x}"
ENV_ENABLE_PREVIEW_VAL="${ENABLE_PREVIEW_SINKS-}"
ENV_NON_MPX_SAMPLE_RATE_SET="${NON_MPX_SAMPLE_RATE+x}"
ENV_NON_MPX_SAMPLE_RATE_VAL="${NON_MPX_SAMPLE_RATE-}"
ENV_PROGRAM2_ENABLED_SET="${PROGRAM2_ENABLED+x}"
ENV_PROGRAM2_ENABLED_VAL="${PROGRAM2_ENABLED-}"
ENV_P1_INGEST_DELAY_SET="${P1_INGEST_DELAY_SEC+x}"
ENV_P1_INGEST_DELAY_VAL="${P1_INGEST_DELAY_SEC-}"
ENV_P2_INGEST_DELAY_SET="${P2_INGEST_DELAY_SEC+x}"
ENV_P2_INGEST_DELAY_VAL="${P2_INGEST_DELAY_SEC-}"
ENV_OMPX_PASSWORD_SET="${OMPX_USER_PASSWORD+x}"
ENV_OMPX_PASSWORD_VAL="${OMPX_USER_PASSWORD-}"
ENV_MULTIBAND_PROFILE_SET="${MULTIBAND_PROFILE+x}"
ENV_MULTIBAND_PROFILE_VAL="${MULTIBAND_PROFILE-}"
ENV_MODULES_DIR_SET="${MODULES_DIR+x}"
ENV_MODULES_DIR_VAL="${MODULES_DIR-}"
ENV_OMPX_STEREO_BACKEND_SET="${OMPX_STEREO_BACKEND+x}"
ENV_OMPX_STEREO_BACKEND_VAL="${OMPX_STEREO_BACKEND-}"
ENV_OMPX_WRAPPER_RDS_ENABLE_SET="${OMPX_WRAPPER_RDS_ENABLE+x}"
ENV_OMPX_WRAPPER_RDS_ENABLE_VAL="${OMPX_WRAPPER_RDS_ENABLE-}"
ENV_OMPX_WRAPPER_RDS_ENCODER_CMD_SET="${OMPX_WRAPPER_RDS_ENCODER_CMD+x}"
ENV_OMPX_WRAPPER_RDS_ENCODER_CMD_VAL="${OMPX_WRAPPER_RDS_ENCODER_CMD-}"
ENV_OMPX_WRAPPER_SAMPLE_RATE_SET="${OMPX_WRAPPER_SAMPLE_RATE+x}"
ENV_OMPX_WRAPPER_SAMPLE_RATE_VAL="${OMPX_WRAPPER_SAMPLE_RATE-}"
ENV_OMPX_WRAPPER_PILOT_LEVEL_SET="${OMPX_WRAPPER_PILOT_LEVEL+x}"
ENV_OMPX_WRAPPER_PILOT_LEVEL_VAL="${OMPX_WRAPPER_PILOT_LEVEL-}"
ENV_OMPX_WRAPPER_RDS_LEVEL_SET="${OMPX_WRAPPER_RDS_LEVEL+x}"
ENV_OMPX_WRAPPER_RDS_LEVEL_VAL="${OMPX_WRAPPER_RDS_LEVEL-}"
ENV_OMPX_WRAPPER_PRESET_SET="${OMPX_WRAPPER_PRESET+x}"
ENV_OMPX_WRAPPER_PRESET_VAL="${OMPX_WRAPPER_PRESET-}"
ENV_OMPX_FM_PREEMPHASIS_SET="${OMPX_FM_PREEMPHASIS+x}"
ENV_OMPX_FM_PREEMPHASIS_VAL="${OMPX_FM_PREEMPHASIS-}"
ENV_OMPX_WEB_UI_ENABLE_SET="${OMPX_WEB_UI_ENABLE+x}"
ENV_OMPX_WEB_UI_ENABLE_VAL="${OMPX_WEB_UI_ENABLE-}"
ENV_OMPX_WEB_BIND_SET="${OMPX_WEB_BIND+x}"
ENV_OMPX_WEB_BIND_VAL="${OMPX_WEB_BIND-}"
ENV_OMPX_WEB_PORT_SET="${OMPX_WEB_PORT+x}"
ENV_OMPX_WEB_PORT_VAL="${OMPX_WEB_PORT-}"
ENV_OMPX_WEB_WHITELIST_SET="${OMPX_WEB_WHITELIST+x}"
ENV_OMPX_WEB_WHITELIST_VAL="${OMPX_WEB_WHITELIST-}"
ENV_OMPX_WEB_AUTH_ENABLE_SET="${OMPX_WEB_AUTH_ENABLE+x}"
ENV_OMPX_WEB_AUTH_ENABLE_VAL="${OMPX_WEB_AUTH_ENABLE-}"
ENV_OMPX_WEB_AUTH_USER_SET="${OMPX_WEB_AUTH_USER+x}"
ENV_OMPX_WEB_AUTH_USER_VAL="${OMPX_WEB_AUTH_USER-}"
ENV_OMPX_WEB_AUTH_PASSWORD_SET="${OMPX_WEB_AUTH_PASSWORD+x}"
ENV_OMPX_WEB_AUTH_PASSWORD_VAL="${OMPX_WEB_AUTH_PASSWORD-}"
ENV_OMPX_WEB_KIOSK_ENABLE_SET="${OMPX_WEB_KIOSK_ENABLE+x}"
ENV_OMPX_WEB_KIOSK_ENABLE_VAL="${OMPX_WEB_KIOSK_ENABLE-}"
ENV_OMPX_WEB_KIOSK_DISPLAY_SET="${OMPX_WEB_KIOSK_DISPLAY+x}"
ENV_OMPX_WEB_KIOSK_DISPLAY_VAL="${OMPX_WEB_KIOSK_DISPLAY-}"
ENV_OMPX_WEB_KIOSK_URL_SET="${OMPX_WEB_KIOSK_URL+x}"
ENV_OMPX_WEB_KIOSK_URL_VAL="${OMPX_WEB_KIOSK_URL-}"

OMPX_USER="ompx"
OMPX_HOME="/home/ompx"
OMPX_LOG_DIR="${OMPX_HOME}/logs"
OMPX_SHELL="/bin/bash"
SYS_SCRIPTS_DIR="/opt/mpx-radio"
FIFOS_DIR="${SYS_SCRIPTS_DIR}/fifos"
SYSTEMD_DIR="/etc/systemd/system"
STEREO_TOOL_WRAPPER="/usr/local/bin/stereo-tool"
STEREO_TOOL_ENTERPRISE_BIN="${OMPX_HOME}/stereo-tool-enterprise/stereo-tool-enterprise"
STEREO_TOOL_ENTERPRISE_LAUNCHER="/usr/local/bin/stereo-tool-enterprise-launch"
STEREO_TOOL_ENTERPRISE_SERVICE="${SYSTEMD_DIR}/stereo-tool-enterprise.service"
OMPX_STREAM_PULL_SERVICE="${SYSTEMD_DIR}/mpx-stream-pull.service"
OMPX_SOURCE1_SERVICE="${SYSTEMD_DIR}/mpx-source1.service"
OMPX_SOURCE2_SERVICE="${SYSTEMD_DIR}/mpx-source2.service"
RDS_SYNC_PROG1_SERVICE="${SYSTEMD_DIR}/rds-sync-prog1.service"
RDS_SYNC_PROG2_SERVICE="${SYSTEMD_DIR}/rds-sync-prog2.service"
OMPX_WEB_UI_SERVICE="${SYSTEMD_DIR}/ompx-web-ui.service"
OMPX_WEB_KIOSK_SERVICE="${SYSTEMD_DIR}/ompx-web-kiosk.service"
OMPX_ADD="/usr/local/bin/ompx_add_source"
ASOUND_CONF_PATH="/etc/asound.conf"
OMPX_AUDIO_UDEV_RULE="/etc/udev/rules.d/70-ompx-audio.rules"
ASOUND_MAP_HELPER="/usr/local/bin/asound-map"
ASOUND_SWITCH_HELPER="/usr/local/bin/asound-switch"
SAMPLE_RATE=192000
NON_MPX_SAMPLE_RATE="${NON_MPX_SAMPLE_RATE:-48000}"
CRON_SLEEP=10

# These can be overridden by exporting env vars before running the installer.
RADIO1_URL="${RADIO1_URL:-https://example-icecast.local:8443/radio1.stream}"
RADIO2_URL="${RADIO2_URL:-https://example-icecast.local:8443/radio2.stream}"
AUTO_UPDATE_STREAM_URLS_FROM_HEADER="${AUTO_UPDATE_STREAM_URLS_FROM_HEADER:-true}"
AUTO_START_STREAMS_FROM_HEADER="${AUTO_START_STREAMS_FROM_HEADER:-false}"
STREAM_SETUP_MODE="${STREAM_SETUP_MODE:-header}"
STREAM_ENGINE="${STREAM_ENGINE:-ffmpeg}"
STREAM_SILENCE_MAX_DBFS="${STREAM_SILENCE_MAX_DBFS:--85}"
INGEST_DELAY_SEC="${INGEST_DELAY_SEC:-10}"
P1_INGEST_DELAY_SEC="${P1_INGEST_DELAY_SEC:-}"
P2_INGEST_DELAY_SEC="${P2_INGEST_DELAY_SEC:-}"
ALLOW_PLACEHOLDER_STREAM_OVERWRITE="${ALLOW_PLACEHOLDER_STREAM_OVERWRITE:-false}"
REMOVE_OLD_SINKS="${REMOVE_OLD_SINKS:-false}"
RUN_QUICK_AUDIO_TEST="${RUN_QUICK_AUDIO_TEST:-false}"
STREAM_VALIDATION_ENABLED="${STREAM_VALIDATION_ENABLED:-false}"
ENABLE_DSCA_SINKS="${ENABLE_DSCA_SINKS:-false}"
ENABLE_PREVIEW_SINKS="${ENABLE_PREVIEW_SINKS:-false}"
PROGRAM2_ENABLED="${PROGRAM2_ENABLED:-false}"
FETCH_STEREO_TOOL_ENTERPRISE="${FETCH_STEREO_TOOL_ENTERPRISE:-false}"
STEREO_TOOL_ENTERPRISE_URL="${STEREO_TOOL_ENTERPRISE_URL:-https://download.thimeo.com/ST-Enterprise}"
STEREO_TOOL_DOWNLOAD_DIR="${STEREO_TOOL_DOWNLOAD_DIR:-${OMPX_HOME}/stereo-tool-enterprise}"
STEREO_TOOL_WEB_BIND="${STEREO_TOOL_WEB_BIND:-0.0.0.0}"
STEREO_TOOL_WEB_PORT="${STEREO_TOOL_WEB_PORT:-8081}"
STEREO_TOOL_WEB_WHITELIST="${STEREO_TOOL_WEB_WHITELIST:-0.0.0.0/0}"
STEREO_TOOL_START_LIMIT_PRESET="${STEREO_TOOL_START_LIMIT_PRESET:-balanced}"
STEREO_TOOL_START_LIMIT_INTERVAL_SEC="${STEREO_TOOL_START_LIMIT_INTERVAL_SEC:-60}"
STEREO_TOOL_START_LIMIT_BURST="${STEREO_TOOL_START_LIMIT_BURST:-10}"
ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE="${ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE:-false}"
AUTO_ENABLE_STEREO_TOOL_IF_PRESENT="${AUTO_ENABLE_STEREO_TOOL_IF_PRESENT:-true}"
START_STEREO_TOOL_AFTER_INSTALL="${START_STEREO_TOOL_AFTER_INSTALL:-true}"
OMPX_USER_PASSWORD="${OMPX_USER_PASSWORD:-}"
MODULES_DIR="${MODULES_DIR:-${REPO_ROOT}/modules}"
MULTIBAND_PROFILE="${MULTIBAND_PROFILE:-waxdreams2-5band}"
OMPX_STEREO_BACKEND="${OMPX_STEREO_BACKEND:-ompx-mpx}"
OMPX_WRAPPER_RDS_ENABLE="${OMPX_WRAPPER_RDS_ENABLE:-false}"
OMPX_WRAPPER_RDS_ENCODER_CMD="${OMPX_WRAPPER_RDS_ENCODER_CMD:-}"
OMPX_WRAPPER_SAMPLE_RATE="${OMPX_WRAPPER_SAMPLE_RATE:-192000}"
OMPX_WRAPPER_PILOT_LEVEL="${OMPX_WRAPPER_PILOT_LEVEL:-0.09}"
OMPX_WRAPPER_RDS_LEVEL="${OMPX_WRAPPER_RDS_LEVEL:-0.03}"
OMPX_WRAPPER_PRESET="${OMPX_WRAPPER_PRESET:-balanced}"
OMPX_FM_PREEMPHASIS="${OMPX_FM_PREEMPHASIS:-75}"
OMPX_WEB_UI_ENABLE="${OMPX_WEB_UI_ENABLE:-false}"
OMPX_WEB_BIND="${OMPX_WEB_BIND:-0.0.0.0}"
OMPX_WEB_PORT="${OMPX_WEB_PORT:-8082}"
OMPX_WEB_WHITELIST="${OMPX_WEB_WHITELIST:-127.0.0.1/32,10.0.0.0/8,192.168.0.0/16}"
OMPX_WEB_AUTH_ENABLE="${OMPX_WEB_AUTH_ENABLE:-false}"
OMPX_WEB_AUTH_USER="${OMPX_WEB_AUTH_USER:-ompx}"
OMPX_WEB_AUTH_PASSWORD="${OMPX_WEB_AUTH_PASSWORD:-}"
OMPX_WEB_KIOSK_ENABLE="${OMPX_WEB_KIOSK_ENABLE:-false}"
OMPX_WEB_KIOSK_DISPLAY="${OMPX_WEB_KIOSK_DISPLAY:-:0}"
OMPX_WEB_KIOSK_URL="${OMPX_WEB_KIOSK_URL:-}"
OMPX_WEB_KIOSK_INSTALL_MISSING="false"

MPX_STEREO_FIFO="/tmp/mpx_stereo.pcm"
# Icecast output (MPX mix → Icecast)
ICECAST_HOST="${ICECAST_HOST:-127.0.0.1}"
ICECAST_PORT="${ICECAST_PORT:-8000}"
ICECAST_SOURCE_USER="${ICECAST_SOURCE_USER:-source}"
ICECAST_PASSWORD="${ICECAST_PASSWORD:-}"
ICECAST_ADMIN_USER="${ICECAST_ADMIN_USER:-admin}"
ICECAST_MOUNT="${ICECAST_MOUNT:-/mpx}"
ICECAST_SAMPLE_RATE="${ICECAST_SAMPLE_RATE:-192000}"
ICECAST_BIT_DEPTH="${ICECAST_BIT_DEPTH:-16}"
ICECAST_CODEC="flac"

# --- Ensure processed MPX is streamed to Icecast ---
# --- Install/Update oMPX Web UI HTML ---
# Deploy latest committed index.html from git
echo "[INFO] Installing Nginx and deploying oMPX Web UI..."
apt-get update && apt-get install -y nginx
git show HEAD:encoder/index.html > /var/www/html/index.html
cp /var/www/html/index.html /workspaces/oMPX/encoder/ompx-web-ui.html
# Allow port override via OMPX_WEB_PORT, default 8083
OMPX_WEB_PORT="${OMPX_WEB_PORT:-8083}"
cat > /etc/nginx/sites-available/ompx-web-ui <<EOF
server {
  listen ${OMPX_WEB_PORT} default_server;
  listen [::]:${OMPX_WEB_PORT} default_server;
  server_name _;
  root /var/www/html;
  index index.html;
  location / {
    try_files \$uri \$uri/ =404;
  }
}
EOF
ln -sf /etc/nginx/sites-available/ompx-web-ui /etc/nginx/sites-enabled/ompx-web-ui
rm -f /etc/nginx/sites-enabled/default
# Disable conflicting ompx-8082.conf if present
if [ -f /etc/nginx/sites-enabled/ompx-8082.conf ]; then
  mv /etc/nginx/sites-enabled/ompx-8082.conf /etc/nginx/sites-enabled/ompx-8082.conf.disabled
  echo "[INFO] Disabled conflicting ompx-8082.conf."
fi
systemctl start nginx
systemctl reload nginx
echo "[INFO] oMPX Web UI is now served by Nginx on port ${OMPX_WEB_PORT}."
systemctl restart nginx
if [ "${UPDATE_ONLY:-false}" = true ]; then
  if [ ! -f /var/www/html/index.html ] || [ /workspaces/oMPX/encoder/index.html -nt /var/www/html/index.html ]; then
    cp -f /workspaces/oMPX/encoder/index.html /var/www/html/index.html
    echo "[INFO] (update) Copied index.html to /var/www/html/index.html."
  fi
  if [ ! -f /usr/share/nginx/html/index.html ] || [ /workspaces/oMPX/encoder/index.html -nt /usr/share/nginx/html/index.html ]; then
    cp -f /workspaces/oMPX/encoder/index.html /usr/share/nginx/html/index.html
    echo "[INFO] (update) Copied index.html to /usr/share/nginx/html/index.html."
  fi
else
  cp -f /workspaces/oMPX/encoder/index.html /var/www/html/index.html
  cp -f /workspaces/oMPX/encoder/index.html /usr/share/nginx/html/index.html
  cp -f /workspaces/oMPX/encoder/index.html /var/www/html/index.html
  cp -f /workspaces/oMPX/encoder/index.html /var/www/html/index.html
  echo "[INFO] (overwrite) Copied index.html to all web roots."
fi
mkdir -p /workspaces/oMPX/encoder
cp /var/www/html/index.html /workspaces/oMPX/encoder/ompx-web-ui.html
## Removed hardcoded overwrite of ompx-web-ui.html to preserve latest committed UI
cat > /usr/local/bin/ompx-icecast-mpx.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
FIFO="/tmp/mpx_stereo.pcm"
ICECAST_HOST="${ICECAST_HOST:-127.0.0.1}"
ICECAST_PORT="${ICECAST_PORT:-8000}"
ICECAST_SOURCE_USER="${ICECAST_SOURCE_USER:-source}"
ICECAST_PASSWORD="${ICECAST_PASSWORD:-}"
ICECAST_MOUNT="${ICECAST_MOUNT:-/mpx}"
ICECAST_SAMPLE_RATE="${ICECAST_SAMPLE_RATE:-192000}"
ICECAST_BIT_DEPTH="${ICECAST_BIT_DEPTH:-16}"
ICECAST_CODEC="flac"
while [ ! -p "$FIFO" ]; do sleep 1; done
exec ffmpeg -hide_banner -loglevel warning -f s16le -ar "$ICECAST_SAMPLE_RATE" -ac 2 -i "$FIFO" \
  -c:a flac -sample_fmt s16 -compression_level 5 \
  -content_type audio/flac \
  -ice_name "oMPX MPX" \
  -f flac "icecast://$ICECAST_SOURCE_USER:$ICECAST_PASSWORD@$ICECAST_HOST:$ICECAST_PORT$ICECAST_MOUNT"
EOF
chmod +x /usr/local/bin/ompx-icecast-mpx.sh

# Add systemd service for Icecast streaming
cat > /etc/systemd/system/ompx-icecast-mpx.service <<'EOF'
[Unit]
Description=oMPX MPX to Icecast
After=network.target run_processing_alsa.service

[Service]
Type=simple
User=ompx
ExecStart=/usr/local/bin/ompx-icecast-mpx.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/ompx-icecast-mpx.service
systemctl daemon-reload || true
systemctl enable --now ompx-icecast-mpx.service || true
# ICECAST_MODE: local | remote | disabled
ICECAST_MODE="${ICECAST_MODE:-disabled}"
# ICECAST_INPUT_MODE: auto | alsa | direct_urls
ICECAST_INPUT_MODE="${ICECAST_INPUT_MODE:-auto}"
# ALSA capture endpoints Stereo Tool Enterprise writes its processed output to
ST_OUT_P1="${ST_OUT_P1:-ompx_prg1mpx_cap}"
ST_OUT_P2="${ST_OUT_P2:-ompx_prg2mpx_cap}"
RDS_PROG1_ENABLE="${RDS_PROG1_ENABLE:-false}"
RDS_PROG1_SOURCE="${RDS_PROG1_SOURCE:-url}"
RDS_PROG1_RT_URL="${RDS_PROG1_RT_URL:-}"
RDS_PROG1_ICECAST_STATS_URL="${RDS_PROG1_ICECAST_STATS_URL:-}"
RDS_PROG1_ICECAST_MOUNT="${RDS_PROG1_ICECAST_MOUNT:-}"
RDS_PROG1_INTERVAL_SEC="${RDS_PROG1_INTERVAL_SEC:-5}"
RDS_PROG1_RT_PATH="${RDS_PROG1_RT_PATH:-${OMPX_HOME}/rds/prog1/rt.txt}"
RDS_PROG1_PS="${RDS_PROG1_PS:-OMPXFM1}"
RDS_PROG1_PI="${RDS_PROG1_PI:-1A01}"
RDS_PROG1_PTY="${RDS_PROG1_PTY:-10}"
RDS_PROG1_TP="${RDS_PROG1_TP:-true}"
RDS_PROG1_TA="${RDS_PROG1_TA:-false}"
RDS_PROG1_MS="${RDS_PROG1_MS:-true}"
RDS_PROG1_CT_ENABLE="${RDS_PROG1_CT_ENABLE:-true}"
RDS_PROG1_CT_MODE="${RDS_PROG1_CT_MODE:-local}"
RDS_PROG1_INFO_PATH="${RDS_PROG1_INFO_PATH:-${OMPX_HOME}/rds/prog1/rds-info.json}"
RDS_PROG1_OVERRIDE_PATH="${RDS_PROG1_OVERRIDE_PATH:-${OMPX_HOME}/rds/prog1/rds-override.json}"
RDS_PROG2_ENABLE="${RDS_PROG2_ENABLE:-false}"
RDS_PROG2_SOURCE="${RDS_PROG2_SOURCE:-url}"
RDS_PROG2_RT_URL="${RDS_PROG2_RT_URL:-}"
RDS_PROG2_ICECAST_STATS_URL="${RDS_PROG2_ICECAST_STATS_URL:-}"
RDS_PROG2_ICECAST_MOUNT="${RDS_PROG2_ICECAST_MOUNT:-}"
RDS_PROG2_INTERVAL_SEC="${RDS_PROG2_INTERVAL_SEC:-5}"
RDS_PROG2_RT_PATH="${RDS_PROG2_RT_PATH:-${OMPX_HOME}/rds/prog2/rt.txt}"
RDS_PROG2_PS="${RDS_PROG2_PS:-OMPXFM2}"
RDS_PROG2_PI="${RDS_PROG2_PI:-1A02}"
RDS_PROG2_PTY="${RDS_PROG2_PTY:-10}"
RDS_PROG2_TP="${RDS_PROG2_TP:-true}"
RDS_PROG2_TA="${RDS_PROG2_TA:-false}"
RDS_PROG2_MS="${RDS_PROG2_MS:-true}"
RDS_PROG2_CT_ENABLE="${RDS_PROG2_CT_ENABLE:-true}"
RDS_PROG2_CT_MODE="${RDS_PROG2_CT_MODE:-local}"
RDS_PROG2_INFO_PATH="${RDS_PROG2_INFO_PATH:-${OMPX_HOME}/rds/prog2/rds-info.json}"
RDS_PROG2_OVERRIDE_PATH="${RDS_PROG2_OVERRIDE_PATH:-${OMPX_HOME}/rds/prog2/rds-override.json}"
CONFIG_OVERWRITE="${CONFIG_OVERWRITE:-true}"
CONFIG_BACKUP="${CONFIG_BACKUP:-true}"
CONFIG_SKIP="${CONFIG_SKIP:-false}"

PROFILE_PATH="${OMPX_HOME}/.profile"
if [ -f "${PROFILE_PATH}" ]; then
  echo "[INFO] Found existing profile at ${PROFILE_PATH}; importing saved stream settings"
  set +u
  # This file is generated by oMPX and used as persistent runtime config.
  . "${PROFILE_PATH}" || true
  set -u
fi
# Output codec is intentionally fixed for FM transport quality.
ICECAST_CODEC="flac"

# Explicit environment values win over imported profile values.
if [ "${ENV_RADIO1_SET}" = "x" ]; then RADIO1_URL="${ENV_RADIO1_VAL}"; fi
if [ "${ENV_RADIO2_SET}" = "x" ]; then RADIO2_URL="${ENV_RADIO2_VAL}"; fi
if [ "${ENV_STREAM_ENGINE_SET}" = "x" ]; then STREAM_ENGINE="${ENV_STREAM_ENGINE_VAL}"; fi
if [ "${ENV_STREAM_SILENCE_SET}" = "x" ]; then STREAM_SILENCE_MAX_DBFS="${ENV_STREAM_SILENCE_VAL}"; fi
if [ "${ENV_ENABLE_DSCA_SET}" = "x" ]; then ENABLE_DSCA_SINKS="${ENV_ENABLE_DSCA_VAL}"; fi
if [ "${ENV_ENABLE_PREVIEW_SET}" = "x" ]; then ENABLE_PREVIEW_SINKS="${ENV_ENABLE_PREVIEW_VAL}"; fi
if [ "${ENV_NON_MPX_SAMPLE_RATE_SET}" = "x" ]; then NON_MPX_SAMPLE_RATE="${ENV_NON_MPX_SAMPLE_RATE_VAL}"; fi
if [ "${ENV_PROGRAM2_ENABLED_SET}" = "x" ]; then PROGRAM2_ENABLED="${ENV_PROGRAM2_ENABLED_VAL}"; fi
if [ "${ENV_P1_INGEST_DELAY_SET}" = "x" ]; then P1_INGEST_DELAY_SEC="${ENV_P1_INGEST_DELAY_VAL}"; fi
if [ "${ENV_P2_INGEST_DELAY_SET}" = "x" ]; then P2_INGEST_DELAY_SEC="${ENV_P2_INGEST_DELAY_VAL}"; fi
if [ "${ENV_OMPX_PASSWORD_SET}" = "x" ]; then OMPX_USER_PASSWORD="${ENV_OMPX_PASSWORD_VAL}"; fi
if [ "${ENV_MULTIBAND_PROFILE_SET}" = "x" ]; then MULTIBAND_PROFILE="${ENV_MULTIBAND_PROFILE_VAL}"; fi
if [ "${ENV_MODULES_DIR_SET}" = "x" ]; then MODULES_DIR="${ENV_MODULES_DIR_VAL}"; fi
if [ "${ENV_OMPX_STEREO_BACKEND_SET}" = "x" ]; then OMPX_STEREO_BACKEND="${ENV_OMPX_STEREO_BACKEND_VAL}"; fi
if [ "${ENV_OMPX_WRAPPER_RDS_ENABLE_SET}" = "x" ]; then OMPX_WRAPPER_RDS_ENABLE="${ENV_OMPX_WRAPPER_RDS_ENABLE_VAL}"; fi
if [ "${ENV_OMPX_WRAPPER_RDS_ENCODER_CMD_SET}" = "x" ]; then OMPX_WRAPPER_RDS_ENCODER_CMD="${ENV_OMPX_WRAPPER_RDS_ENCODER_CMD_VAL}"; fi
if [ "${ENV_OMPX_WRAPPER_SAMPLE_RATE_SET}" = "x" ]; then OMPX_WRAPPER_SAMPLE_RATE="${ENV_OMPX_WRAPPER_SAMPLE_RATE_VAL}"; fi
if [ "${ENV_OMPX_WRAPPER_PILOT_LEVEL_SET}" = "x" ]; then OMPX_WRAPPER_PILOT_LEVEL="${ENV_OMPX_WRAPPER_PILOT_LEVEL_VAL}"; fi
if [ "${ENV_OMPX_WRAPPER_RDS_LEVEL_SET}" = "x" ]; then OMPX_WRAPPER_RDS_LEVEL="${ENV_OMPX_WRAPPER_RDS_LEVEL_VAL}"; fi
if [ "${ENV_OMPX_WRAPPER_PRESET_SET}" = "x" ]; then OMPX_WRAPPER_PRESET="${ENV_OMPX_WRAPPER_PRESET_VAL}"; fi
if [ "${ENV_OMPX_FM_PREEMPHASIS_SET}" = "x" ]; then OMPX_FM_PREEMPHASIS="${ENV_OMPX_FM_PREEMPHASIS_VAL}"; fi
if [ "${ENV_OMPX_WEB_UI_ENABLE_SET}" = "x" ]; then OMPX_WEB_UI_ENABLE="${ENV_OMPX_WEB_UI_ENABLE_VAL}"; fi
if [ "${ENV_OMPX_WEB_BIND_SET}" = "x" ]; then OMPX_WEB_BIND="${ENV_OMPX_WEB_BIND_VAL}"; fi
if [ "${ENV_OMPX_WEB_PORT_SET}" = "x" ]; then OMPX_WEB_PORT="${ENV_OMPX_WEB_PORT_VAL}"; fi
if [ "${ENV_OMPX_WEB_WHITELIST_SET}" = "x" ]; then OMPX_WEB_WHITELIST="${ENV_OMPX_WEB_WHITELIST_VAL}"; fi
if [ "${ENV_OMPX_WEB_AUTH_ENABLE_SET}" = "x" ]; then OMPX_WEB_AUTH_ENABLE="${ENV_OMPX_WEB_AUTH_ENABLE_VAL}"; fi
if [ "${ENV_OMPX_WEB_AUTH_USER_SET}" = "x" ]; then OMPX_WEB_AUTH_USER="${ENV_OMPX_WEB_AUTH_USER_VAL}"; fi
if [ "${ENV_OMPX_WEB_AUTH_PASSWORD_SET}" = "x" ]; then OMPX_WEB_AUTH_PASSWORD="${ENV_OMPX_WEB_AUTH_PASSWORD_VAL}"; fi
if [ "${ENV_OMPX_WEB_KIOSK_ENABLE_SET}" = "x" ]; then OMPX_WEB_KIOSK_ENABLE="${ENV_OMPX_WEB_KIOSK_ENABLE_VAL}"; fi
if [ "${ENV_OMPX_WEB_KIOSK_DISPLAY_SET}" = "x" ]; then OMPX_WEB_KIOSK_DISPLAY="${ENV_OMPX_WEB_KIOSK_DISPLAY_VAL}"; fi
if [ "${ENV_OMPX_WEB_KIOSK_URL_SET}" = "x" ]; then OMPX_WEB_KIOSK_URL="${ENV_OMPX_WEB_KIOSK_URL_VAL}"; fi
ENABLE_DSCA_SINKS="${ENABLE_DSCA_SINKS,,}"
ENABLE_PREVIEW_SINKS="${ENABLE_PREVIEW_SINKS,,}"
PROGRAM2_ENABLED="${PROGRAM2_ENABLED,,}"
if [ "${ENABLE_DSCA_SINKS}" != "true" ] && [ "${ENABLE_DSCA_SINKS}" != "false" ]; then
  echo "[WARNING] Invalid ENABLE_DSCA_SINKS='${ENABLE_DSCA_SINKS}'; defaulting to false"
  ENABLE_DSCA_SINKS="false"
fi
if [ "${ENABLE_PREVIEW_SINKS}" != "true" ] && [ "${ENABLE_PREVIEW_SINKS}" != "false" ]; then
  echo "[WARNING] Invalid ENABLE_PREVIEW_SINKS='${ENABLE_PREVIEW_SINKS}'; defaulting to false"
  ENABLE_PREVIEW_SINKS="false"
fi
if [ "${PROGRAM2_ENABLED}" != "true" ] && [ "${PROGRAM2_ENABLED}" != "false" ]; then
  echo "[WARNING] Invalid PROGRAM2_ENABLED='${PROGRAM2_ENABLED}'; defaulting to false"
  PROGRAM2_ENABLED="false"
fi
if ! [[ "${NON_MPX_SAMPLE_RATE}" =~ ^[0-9]+$ ]] || [ "${NON_MPX_SAMPLE_RATE}" -lt 8000 ] || [ "${NON_MPX_SAMPLE_RATE}" -gt 192000 ]; then
  echo "[WARNING] Invalid NON_MPX_SAMPLE_RATE='${NON_MPX_SAMPLE_RATE}'; defaulting to 48000"
  NON_MPX_SAMPLE_RATE="48000"
fi
if ! [[ "${INGEST_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  echo "[WARNING] Invalid INGEST_DELAY_SEC='${INGEST_DELAY_SEC}'; defaulting to 10"
  INGEST_DELAY_SEC="10"
fi
if ! [[ "${ICECAST_BIT_DEPTH}" =~ ^(16|24)$ ]]; then
  echo "[WARNING] Invalid ICECAST_BIT_DEPTH='${ICECAST_BIT_DEPTH}'; defaulting to 16"
  ICECAST_BIT_DEPTH="16"
fi
ICECAST_INPUT_MODE="${ICECAST_INPUT_MODE,,}"
if [ "${ICECAST_INPUT_MODE}" != "auto" ] && [ "${ICECAST_INPUT_MODE}" != "alsa" ] && [ "${ICECAST_INPUT_MODE}" != "direct_urls" ]; then
  echo "[WARNING] Invalid ICECAST_INPUT_MODE='${ICECAST_INPUT_MODE}'; defaulting to auto"
  ICECAST_INPUT_MODE="auto"
fi
if [ -n "${P1_INGEST_DELAY_SEC}" ] && ! [[ "${P1_INGEST_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  echo "[WARNING] Invalid P1_INGEST_DELAY_SEC='${P1_INGEST_DELAY_SEC}'; using INGEST_DELAY_SEC (${INGEST_DELAY_SEC})"
  P1_INGEST_DELAY_SEC=""
fi
if [ -n "${P2_INGEST_DELAY_SEC}" ] && ! [[ "${P2_INGEST_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  echo "[WARNING] Invalid P2_INGEST_DELAY_SEC='${P2_INGEST_DELAY_SEC}'; using INGEST_DELAY_SEC (${INGEST_DELAY_SEC})"
  P2_INGEST_DELAY_SEC=""
fi
case "${MULTIBAND_PROFILE}" in
  waxdreams2-5band|waxdreams2-safe|fm-loud|voice-safe|classic-3band|decoder-clean|talk-heavy|music-heavy)
    ;;
  *)
    echo "[WARNING] Invalid MULTIBAND_PROFILE='${MULTIBAND_PROFILE}'; defaulting to waxdreams2-5band"
    MULTIBAND_PROFILE="waxdreams2-5band"
    ;;
esac
OMPX_STEREO_BACKEND="${OMPX_STEREO_BACKEND,,}"
OMPX_WRAPPER_RDS_ENABLE="${OMPX_WRAPPER_RDS_ENABLE,,}"
if [ "${OMPX_STEREO_BACKEND}" != "stereotool" ] && [ "${OMPX_STEREO_BACKEND}" != "ompx-mpx" ] && [ "${OMPX_STEREO_BACKEND}" != "passthrough" ]; then
  echo "[WARNING] Invalid OMPX_STEREO_BACKEND='${OMPX_STEREO_BACKEND}'; defaulting to ompx-mpx"
  OMPX_STEREO_BACKEND="ompx-mpx"
fi
if [ "${OMPX_WRAPPER_RDS_ENABLE}" != "true" ] && [ "${OMPX_WRAPPER_RDS_ENABLE}" != "false" ]; then
  echo "[WARNING] Invalid OMPX_WRAPPER_RDS_ENABLE='${OMPX_WRAPPER_RDS_ENABLE}'; defaulting to false"
  OMPX_WRAPPER_RDS_ENABLE="false"
fi
if ! [[ "${OMPX_WRAPPER_SAMPLE_RATE}" =~ ^[0-9]+$ ]] || [ "${OMPX_WRAPPER_SAMPLE_RATE}" -lt 32000 ] || [ "${OMPX_WRAPPER_SAMPLE_RATE}" -gt 384000 ]; then
  echo "[WARNING] Invalid OMPX_WRAPPER_SAMPLE_RATE='${OMPX_WRAPPER_SAMPLE_RATE}'; defaulting to 192000"
  OMPX_WRAPPER_SAMPLE_RATE="192000"
fi
if ! awk -v v="${OMPX_WRAPPER_PILOT_LEVEL}" 'BEGIN{exit !(v>=0 && v<=0.2)}'; then
  echo "[WARNING] Invalid OMPX_WRAPPER_PILOT_LEVEL='${OMPX_WRAPPER_PILOT_LEVEL}'; defaulting to 0.09"
  OMPX_WRAPPER_PILOT_LEVEL="0.09"
fi
if ! awk -v v="${OMPX_WRAPPER_RDS_LEVEL}" 'BEGIN{exit !(v>=0 && v<=0.1)}'; then
  echo "[WARNING] Invalid OMPX_WRAPPER_RDS_LEVEL='${OMPX_WRAPPER_RDS_LEVEL}'; defaulting to 0.03"
  OMPX_WRAPPER_RDS_LEVEL="0.03"
fi
OMPX_WRAPPER_PRESET="${OMPX_WRAPPER_PRESET,,}"
if [ "${OMPX_WRAPPER_PRESET}" != "conservative" ] && [ "${OMPX_WRAPPER_PRESET}" != "balanced" ] && [ "${OMPX_WRAPPER_PRESET}" != "hot" ] && [ "${OMPX_WRAPPER_PRESET}" != "speech" ]; then
  echo "[WARNING] Invalid OMPX_WRAPPER_PRESET='${OMPX_WRAPPER_PRESET}'; defaulting to balanced"
  OMPX_WRAPPER_PRESET="balanced"
fi

generate_secure_password(){
  local length="${1:-24}"
  local generated=""
  if command -v openssl >/dev/null 2>&1; then
    generated="$(openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c "${length}" || true)"
  fi
  if [ -z "${generated}" ] && [ -r /dev/urandom ]; then
    generated="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${length}" || true)"
  fi
  if [ -z "${generated}" ]; then
    generated="$(date +%s%N | sha256sum | awk '{print $1}' | head -c "${length}" || true)"
  fi
  if [ -z "${generated}" ]; then
    generated="ompx$(date +%s)"
  fi
  printf '%s' "${generated}"
}

OMPX_FM_PREEMPHASIS="${OMPX_FM_PREEMPHASIS,,}"
OMPX_WEB_UI_ENABLE="${OMPX_WEB_UI_ENABLE,,}"
OMPX_WEB_AUTH_ENABLE="${OMPX_WEB_AUTH_ENABLE,,}"
OMPX_WEB_KIOSK_ENABLE="${OMPX_WEB_KIOSK_ENABLE,,}"
if [ "${OMPX_FM_PREEMPHASIS}" = "75us" ]; then OMPX_FM_PREEMPHASIS="75"; fi
if [ "${OMPX_FM_PREEMPHASIS}" = "50us" ]; then OMPX_FM_PREEMPHASIS="50"; fi
if [ "${OMPX_FM_PREEMPHASIS}" != "75" ] && [ "${OMPX_FM_PREEMPHASIS}" != "50" ] && [ "${OMPX_FM_PREEMPHASIS}" != "off" ]; then
  echo "[WARNING] Invalid OMPX_FM_PREEMPHASIS='${OMPX_FM_PREEMPHASIS}'; defaulting to 75"
  OMPX_FM_PREEMPHASIS="75"
fi
if [ "${OMPX_WEB_UI_ENABLE}" != "true" ] && [ "${OMPX_WEB_UI_ENABLE}" != "false" ]; then
  echo "[WARNING] Invalid OMPX_WEB_UI_ENABLE='${OMPX_WEB_UI_ENABLE}'; defaulting to false"
  OMPX_WEB_UI_ENABLE="false"
fi
if [ "${OMPX_WEB_AUTH_ENABLE}" != "true" ] && [ "${OMPX_WEB_AUTH_ENABLE}" != "false" ]; then
  echo "[WARNING] Invalid OMPX_WEB_AUTH_ENABLE='${OMPX_WEB_AUTH_ENABLE}'; defaulting to false"
  OMPX_WEB_AUTH_ENABLE="false"
fi
if ! [[ "${OMPX_WEB_PORT}" =~ ^[0-9]+$ ]] || [ "${OMPX_WEB_PORT}" -lt 1 ] || [ "${OMPX_WEB_PORT}" -gt 65535 ]; then
  echo "[WARNING] Invalid OMPX_WEB_PORT='${OMPX_WEB_PORT}'; defaulting to 8082"
  OMPX_WEB_PORT="8082"
fi
if [ -z "${OMPX_WEB_AUTH_USER}" ]; then
  OMPX_WEB_AUTH_USER="ompx"
fi
if [ "${OMPX_WEB_AUTH_ENABLE}" = "true" ] && [ -z "${OMPX_WEB_AUTH_PASSWORD}" ]; then
  OMPX_WEB_AUTH_PASSWORD="$(generate_secure_password 24)"
  echo "[INFO] OMPX web auth enabled with generated password for user ${OMPX_WEB_AUTH_USER}"
fi
if [ "${OMPX_WEB_KIOSK_ENABLE}" != "true" ] && [ "${OMPX_WEB_KIOSK_ENABLE}" != "false" ]; then
  echo "[WARNING] Invalid OMPX_WEB_KIOSK_ENABLE='${OMPX_WEB_KIOSK_ENABLE}'; defaulting to false"
  OMPX_WEB_KIOSK_ENABLE="false"
fi
if [ -z "${OMPX_WEB_KIOSK_DISPLAY}" ]; then
  OMPX_WEB_KIOSK_DISPLAY=":0"
fi
if [ -z "${OMPX_WEB_KIOSK_URL}" ]; then
  OMPX_WEB_KIOSK_URL="http://127.0.0.1:${OMPX_WEB_PORT}/"
fi
if [ "${OMPX_WEB_UI_ENABLE}" != "true" ] && [ "${OMPX_WEB_KIOSK_ENABLE}" = "true" ]; then
  echo "[WARNING] OMPX_WEB_KIOSK_ENABLE=true requires OMPX_WEB_UI_ENABLE=true; disabling kiosk"
  OMPX_WEB_KIOSK_ENABLE="false"
fi
if [ -z "${ICECAST_PASSWORD}" ]; then
  ICECAST_PASSWORD="$(generate_secure_password 24)"
  echo "[INFO] ICECAST_PASSWORD not provided; generated a secure random password"
fi

RDS_PROG1_PS="${RDS_PROG1_PS:0:8}"
RDS_PROG2_PS="${RDS_PROG2_PS:0:8}"
RDS_PROG1_PI="${RDS_PROG1_PI^^}"
RDS_PROG2_PI="${RDS_PROG2_PI^^}"
if ! [[ "${RDS_PROG1_PI}" =~ ^[0-9A-F]{4}$ ]]; then
  echo "[WARNING] Invalid RDS_PROG1_PI='${RDS_PROG1_PI}'; defaulting to 1A01"
  RDS_PROG1_PI="1A01"
fi
if ! [[ "${RDS_PROG2_PI}" =~ ^[0-9A-F]{4}$ ]]; then
  echo "[WARNING] Invalid RDS_PROG2_PI='${RDS_PROG2_PI}'; defaulting to 1A02"
  RDS_PROG2_PI="1A02"
fi
if ! [[ "${RDS_PROG1_PTY}" =~ ^[0-9]+$ ]] || [ "${RDS_PROG1_PTY}" -lt 0 ] || [ "${RDS_PROG1_PTY}" -gt 31 ]; then
  echo "[WARNING] Invalid RDS_PROG1_PTY='${RDS_PROG1_PTY}'; defaulting to 10"
  RDS_PROG1_PTY="10"
fi
if ! [[ "${RDS_PROG2_PTY}" =~ ^[0-9]+$ ]] || [ "${RDS_PROG2_PTY}" -lt 0 ] || [ "${RDS_PROG2_PTY}" -gt 31 ]; then
  echo "[WARNING] Invalid RDS_PROG2_PTY='${RDS_PROG2_PTY}'; defaulting to 10"
  RDS_PROG2_PTY="10"
fi
RDS_PROG1_TP="${RDS_PROG1_TP,,}"; [ "${RDS_PROG1_TP}" = "true" ] || RDS_PROG1_TP="false"
RDS_PROG1_TA="${RDS_PROG1_TA,,}"; [ "${RDS_PROG1_TA}" = "true" ] || RDS_PROG1_TA="false"
RDS_PROG1_MS="${RDS_PROG1_MS,,}"; [ "${RDS_PROG1_MS}" = "true" ] || RDS_PROG1_MS="false"
RDS_PROG2_TP="${RDS_PROG2_TP,,}"; [ "${RDS_PROG2_TP}" = "true" ] || RDS_PROG2_TP="false"
RDS_PROG2_TA="${RDS_PROG2_TA,,}"; [ "${RDS_PROG2_TA}" = "true" ] || RDS_PROG2_TA="false"
RDS_PROG2_MS="${RDS_PROG2_MS,,}"; [ "${RDS_PROG2_MS}" = "true" ] || RDS_PROG2_MS="false"
RDS_PROG1_CT_ENABLE="${RDS_PROG1_CT_ENABLE,,}"; [ "${RDS_PROG1_CT_ENABLE}" = "true" ] || RDS_PROG1_CT_ENABLE="false"
RDS_PROG2_CT_ENABLE="${RDS_PROG2_CT_ENABLE,,}"; [ "${RDS_PROG2_CT_ENABLE}" = "true" ] || RDS_PROG2_CT_ENABLE="false"
RDS_PROG1_CT_MODE="${RDS_PROG1_CT_MODE,,}"; [ "${RDS_PROG1_CT_MODE}" = "utc" ] || RDS_PROG1_CT_MODE="local"
RDS_PROG2_CT_MODE="${RDS_PROG2_CT_MODE,,}"; [ "${RDS_PROG2_CT_MODE}" = "utc" ] || RDS_PROG2_CT_MODE="local"

if [ "${OMPX_STEREO_BACKEND}" != "stereotool" ]; then
  # When using the internal oMPX wrapper chain, Stereo Tool Enterprise must not auto-start.
  ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE="false"
  AUTO_ENABLE_STEREO_TOOL_IF_PRESENT="false"
  START_STEREO_TOOL_AFTER_INSTALL="false"
fi
STREAM_ENGINE="ffmpeg"

OS_ID="unknown"
if [ -r /etc/os-release ]; then
  . /etc/os-release
  OS_ID="${ID:-unknown}"
fi
IS_PROXMOX=false
[[ "$(uname -r)" == *"pve"* ]] && IS_PROXMOX=true
KERNEL_HELPER_PACKAGE=""
LOOPBACK_CARD_REF="${LOOPBACK_CARD_REF:-Loopback}"
CHANNEL_MODE_SET_BY_PROMPT="false"

_log(){
  logger -t mpx "$*" 2>/dev/null || true
  echo "$(date +'%F %T') $*"
}

have_crontab(){
  command -v crontab >/dev/null 2>&1
}

has_systemd(){
  command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

apply_ompx_user_password(){
  local new_password="$1"
  if [ -z "${new_password}" ]; then
    return 0
  fi
  if ! id -u "${OMPX_USER}" >/dev/null 2>&1; then
    echo "[WARNING] Cannot set password: user ${OMPX_USER} does not exist"
    return 0
  fi
  if command -v chpasswd >/dev/null 2>&1; then
    if printf '%s:%s\n' "${OMPX_USER}" "${new_password}" | chpasswd; then
      echo "[SUCCESS] Password set for user ${OMPX_USER}"
    else
      echo "[WARNING] Failed to set password for user ${OMPX_USER}"
    fi
  else
    echo "[WARNING] chpasswd not found; cannot set password for ${OMPX_USER}"
  fi
}

ensure_ompx_alsa_access(){
  if getent group audio >/dev/null 2>&1; then
    usermod -aG audio "${OMPX_USER}" >/dev/null 2>&1 || true
    gpasswd -a "${OMPX_USER}" audio >/dev/null 2>&1 || true
  fi

  mkdir -p "${OMPX_HOME}" || true
  if [ -e "${ASOUND_CONF_PATH}" ]; then
    ln -sfn "${ASOUND_CONF_PATH}" "${OMPX_HOME}/.asoundrc" || true
    chown -h "${OMPX_USER}:${OMPX_USER}" "${OMPX_HOME}/.asoundrc" || true
  fi

  if mkdir -p "$(dirname "${OMPX_AUDIO_UDEV_RULE}")" 2>/dev/null; then
    cat > "${OMPX_AUDIO_UDEV_RULE}" <<'UDEVRULE' || true
SUBSYSTEM=="sound", GROUP="audio", MODE="0660"
UDEVRULE
    chmod 644 "${OMPX_AUDIO_UDEV_RULE}" || true
  else
    echo "[WARNING] Could not create udev rules directory for ${OMPX_AUDIO_UDEV_RULE}; continuing without custom sound udev rule"
  fi

  if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules >/dev/null 2>&1 || true
    udevadm trigger --subsystem-match=sound >/dev/null 2>&1 || true
  fi

  if [ -d /dev/snd ]; then
    chgrp -R audio /dev/snd >/dev/null 2>&1 || true
    chmod -R g+rw /dev/snd >/dev/null 2>&1 || true
  fi
}

download_stereo_tool_enterprise(){
  local url="$1"
  local dl_dir="$2"
  local target_bin="$3"
  local target_tmp="${target_bin}.download"
  local target=""

  if [ -z "${url}" ]; then
    echo "[WARNING] Stereo Tool Enterprise download requested but no URL was provided; skipping"
    return 0
  fi

  case "${url}" in
    http://*|https://*) ;;
    *)
      echo "[WARNING] Stereo Tool Enterprise URL must start with http:// or https://; skipping"
      return 0
      ;;
  esac

  mkdir -p "${dl_dir}"
  target="${target_tmp}"

  echo "[INFO] Downloading Stereo Tool Enterprise artifact..."
  if command -v curl >/dev/null 2>&1; then
    if ! curl -fL --retry 3 --connect-timeout 20 -o "${target}" "${url}"; then
      echo "[WARNING] Stereo Tool Enterprise download failed via curl"
      return 0
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -O "${target}" "${url}"; then
      echo "[WARNING] Stereo Tool Enterprise download failed via wget"
      return 0
    fi
  else
    echo "[WARNING] Neither curl nor wget is available; skipping Stereo Tool Enterprise download"
    return 0
  fi

  mv -f "${target_tmp}" "${target_bin}"
  chmod 755 "${target_bin}" || true
  chown "${OMPX_USER}:${OMPX_USER}" "${target_bin}" || true
  echo "[SUCCESS] Downloaded Stereo Tool Enterprise binary to ${target_bin}"
}

install_stereo_tool_enterprise_service(){
  local bin_path="$1"
  local launcher_path="$2"
  local bind_ip="$3"
  local web_port="$4"
  local whitelist="$5"
  local start_limit_interval="$6"
  local start_limit_burst="$7"

  if [ ! -x "${bin_path}" ]; then
    echo "[WARNING] Stereo Tool Enterprise binary not executable at ${bin_path}; skipping service install"
    return 0
  fi

  # Ensure ALSA config is promoted so service can see named sinks
  if [ -f /etc/asound.conf.ompx-staged ] && ( [ ! -f /etc/asound.conf ] || [ ! -s /etc/asound.conf ] ); then
    cp -f /etc/asound.conf.ompx-staged /etc/asound.conf
    chmod 644 /etc/asound.conf
    echo "[INFO] Promoted staged ALSA config for Stereo Tool service"
  fi

  cat > "${launcher_path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
BIN="${bin_path}"
BIND_IP="${bind_ip}"
WEB_PORT="${web_port}"
WHITELIST="${whitelist}"

if [ ! -x "${bin_path}" ]; then
  echo "stereo-tool-enterprise-launch: binary not executable: ${bin_path}" >&2
  exit 126
fi

# Prefer oMPX ALSA map when available, but fall back to default ALSA config
# if that map is missing or invalid so device enumeration never disappears.
if [ -r /etc/asound.conf ]; then
  export ALSA_CONFIG_PATH=/etc/asound.conf
fi
_alsa_probe_l="\$(aplay -l 2>&1 || true)"
_alsa_probe_L="\$(aplay -L 2>&1 || true)"
if printf '%s\n%s\n' "\${_alsa_probe_l}" "\${_alsa_probe_L}" | grep -qiE 'Invalid CTL|control open \([0-9]+\): No such file|Unknown PCM'; then
  unset ALSA_CONFIG_PATH || true
elif [ -z "\${_alsa_probe_L}" ]; then
  unset ALSA_CONFIG_PATH || true
fi

# Debug: Check ALSA visibility
{
  echo "stereo-tool-enterprise-launch: ALSA diagnostics"
  echo "  User: \$(whoami)"
  echo "  Groups: \$(id -nG)"
  echo "  ALSA_CONFIG_PATH: \${ALSA_CONFIG_PATH:-<unset>}"
  echo "  /dev/snd permissions: \$(ls -ld /dev/snd 2>/dev/null || echo 'N/A')"
  echo "  /dev/snd contents: \$(ls -la /dev/snd 2>/dev/null | wc -l) items"
  echo "  aplay -l output:"
  aplay -l 2>&1 | head -10 || true
  echo "  aplay -L output (friendly names):"
  aplay -L 2>&1 | head -20 || true
  echo "  oMPX playback names visible to Stereo Tool:"
  aplay -L 2>&1 | grep -E '^ompx_|^program' || true
  echo "  oMPX capture names visible to Stereo Tool:"
  arecord -L 2>&1 | grep -E '^ompx_|^program' || true
} >&2

help_text="\$(${bin_path} --help 2>&1 || true)"
args=()

# Bind/listen address flag variants
if printf '%s\n' "\${help_text}" | grep -q -- '--listen-ip'; then
  args+=(--listen-ip "\${BIND_IP}")
elif printf '%s\n' "\${help_text}" | grep -q -- '--bind-address'; then
  args+=(--bind-address "\${BIND_IP}")
elif printf '%s\n' "\${help_text}" | grep -q -- '--web-address'; then
  args+=(--web-address "\${BIND_IP}")
fi

# Port flag variants
if printf '%s\n' "\${help_text}" | grep -q -- '--port'; then
  args+=(--port "\${WEB_PORT}")
elif printf '%s\n' "\${help_text}" | grep -q -- '--http-port'; then
  args+=(--http-port "\${WEB_PORT}")
elif printf '%s\n' "\${help_text}" | grep -q -- '--web-port'; then
  args+=(--web-port "\${WEB_PORT}")
fi

# Allowed client IP flag variants
if printf '%s\n' "\${help_text}" | grep -q -- '--allow-from'; then
  args+=(--allow-from "\${WHITELIST}")
elif printf '%s\n' "\${help_text}" | grep -q -- '--allowed-ip'; then
  args+=(--allowed-ip "\${WHITELIST}")
elif printf '%s\n' "\${help_text}" | grep -q -- '--web-allow'; then
  args+=(--web-allow "\${WHITELIST}")
fi

# Optional operator-provided args (space-separated), e.g. ST_ENTERPRISE_EXTRA_ARGS='--foo bar'
set -- "\${BIN}" "\${args[@]}"
if [ -n "\${ST_ENTERPRISE_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2086
  set -- "\$@" \${ST_ENTERPRISE_EXTRA_ARGS}
fi

echo "stereo-tool-enterprise-launch: exec \$*" >&2
exec "\$@"
EOF
  chmod 755 "${launcher_path}"
  chown root:root "${launcher_path}"

  cat > "${STEREO_TOOL_ENTERPRISE_SERVICE}" <<EOF
[Unit]
Description=Stereo Tool Enterprise Web Service
After=network-online.target
Wants=network-online.target
After=sound.target
Wants=sound.target
StartLimitIntervalSec=${start_limit_interval}
StartLimitBurst=${start_limit_burst}

[Service]
Type=simple
User=${OMPX_USER}
Group=${OMPX_USER}
SupplementaryGroups=audio
PermissionsStartOnly=true
WorkingDirectory=${OMPX_HOME}
Environment=HOME=${OMPX_HOME}
ExecStartPre=/bin/sh -c 'usermod -aG audio ${OMPX_USER} >/dev/null 2>&1 || true'
ExecStartPre=/bin/sh -c 'if command -v udevadm >/dev/null 2>&1; then udevadm control --reload-rules >/dev/null 2>&1 || true; udevadm trigger --subsystem-match=sound >/dev/null 2>&1 || true; fi'
ExecStartPre=/bin/sh -c 'if [ -d /dev/snd ]; then chgrp -R audio /dev/snd >/dev/null 2>&1 || true; chmod -R g+rw /dev/snd >/dev/null 2>&1 || true; fi'
ExecStartPre=/bin/sh -c 'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do [ -d /dev/snd ] && ls -A /dev/snd >/dev/null 2>&1 && exit 0; sleep 1; done; exit 0'
ExecStartPre=/bin/sh -c 'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do runuser -u ${OMPX_USER} -- aplay -l >/dev/null 2>&1 && exit 0; sleep 1; done; exit 0'
ExecStart=${launcher_path}
Restart=on-failure
RestartSec=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 "${STEREO_TOOL_ENTERPRISE_SERVICE}"
  chown root:root "${STEREO_TOOL_ENTERPRISE_SERVICE}"
  echo "[SUCCESS] Installed Stereo Tool Enterprise service unit: ${STEREO_TOOL_ENTERPRISE_SERVICE}"
}

apply_stereo_tool_start_limit_preset(){
  local preset="${STEREO_TOOL_START_LIMIT_PRESET,,}"
  case "${preset}" in
    strict)
      STEREO_TOOL_START_LIMIT_INTERVAL_SEC=60
      STEREO_TOOL_START_LIMIT_BURST=5
      ;;
    balanced|"")
      STEREO_TOOL_START_LIMIT_INTERVAL_SEC=60
      STEREO_TOOL_START_LIMIT_BURST=10
      ;;
    lenient)
      STEREO_TOOL_START_LIMIT_INTERVAL_SEC=120
      STEREO_TOOL_START_LIMIT_BURST=20
      ;;
    custom)
      ;;
    *)
      echo "[WARNING] Unknown STEREO_TOOL_START_LIMIT_PRESET='${STEREO_TOOL_START_LIMIT_PRESET}', keeping explicit interval/burst values"
      ;;
  esac
  echo "[INFO] Stereo Tool start-limit policy: preset=${STEREO_TOOL_START_LIMIT_PRESET}, interval=${STEREO_TOOL_START_LIMIT_INTERVAL_SEC}s, burst=${STEREO_TOOL_START_LIMIT_BURST}"
}

configure_icecast_dialog(){
  prompt_helper _ice_mode "Select Icecast mode: [L=Local, R=Remote, S=Skip] (default S): " S 60
  _ice_mode=${_ice_mode^^}

  case "${_ice_mode}" in
    L)
      ICECAST_MODE="local"
      ICECAST_HOST="127.0.0.1"
      prompt_helper _ice_port "Icecast HTTP port (default 8000): " 8000 60
      [[ "${_ice_port}" =~ ^[0-9]+$ ]] && ICECAST_PORT="${_ice_port}" || ICECAST_PORT=8000
      prompt_helper ICECAST_SOURCE_USER "Icecast source username (default source): " source 60
      prompt_helper _ice_pass "Icecast source password (leave blank for auto-generated): " "" 60
      if [ -n "${_ice_pass}" ]; then
        ICECAST_PASSWORD="${_ice_pass}"
      else
        ICECAST_PASSWORD="$(generate_secure_password 24)"
        echo "[INFO] Generated Icecast source password: ${ICECAST_PASSWORD}"
      fi
      prompt_helper _ice_mount "Mount point (default /mpx): " /mpx 60
      _ice_mount="${_ice_mount:-mpx}"; ICECAST_MOUNT="/${_ice_mount#/}"
      prompt_helper ICECAST_ADMIN_USER "Icecast admin username (default admin): " admin 60
      prompt_helper _ice_admin "Icecast admin password (leave blank for auto-generated): " "" 60
      if [ -n "${_ice_admin}" ]; then
        _ICE_ADMIN_PASS="${_ice_admin}"
      else
        _ICE_ADMIN_PASS="$(generate_secure_password 24)"
        echo "[INFO] Generated Icecast admin password: ${_ICE_ADMIN_PASS}"
      fi
      prompt_helper _ice_clients "Max simultaneous listeners (default 25): " 25 60
      [[ "${_ice_clients}" =~ ^[0-9]+$ ]] && _ICE_MAX_LISTENERS="${_ice_clients}" || _ICE_MAX_LISTENERS=25
      prompt_helper _ICE_STATION "Station name shown to listeners (default oMPX): " oMPX 60
      echo "[INFO] Local Icecast2 → localhost:${ICECAST_PORT}${ICECAST_MOUNT}"
      ;;
    R)
      ICECAST_MODE="remote"
      prompt_helper _ice_host "Remote Icecast hostname or IP: " "" 60
      if [ -z "${_ice_host}" ]; then
        echo "[INFO] No host entered — Icecast mode set to disabled"; ICECAST_MODE="disabled"; return
      fi
      ICECAST_HOST="${_ice_host}"
      prompt_helper _ice_port "Remote Icecast port (default 8000): " 8000 60
      [[ "${_ice_port}" =~ ^[0-9]+$ ]] && ICECAST_PORT="${_ice_port}" || ICECAST_PORT=8000
      prompt_helper ICECAST_SOURCE_USER "Source username (default source): " source 60
      prompt_helper _ice_pass "Source password (leave blank for auto-generated): " "" 60
      if [ -n "${_ice_pass}" ]; then
        ICECAST_PASSWORD="${_ice_pass}"
      else
        ICECAST_PASSWORD="$(generate_secure_password 24)"
        echo "[INFO] Generated remote Icecast source password: ${ICECAST_PASSWORD}"
      fi
      prompt_helper _ice_mount "Mount point (default /mpx): " /mpx 60
      _ice_mount="${_ice_mount:-mpx}"; ICECAST_MOUNT="/${_ice_mount#/}"
      echo "[INFO] Remote Icecast push → ${ICECAST_HOST}:${ICECAST_PORT}${ICECAST_MOUNT}"
      ;;
    *)
      ICECAST_MODE="disabled"
      echo "[INFO] Icecast skipped — edit /home/ompx/.profile and restart mpx-mix.service later"
      return
      ;;
  esac

  prompt_helper _ice_sr "Output sample rate Hz (default 192000, use 48000 for standard): " 192000 60
  [[ "${_ice_sr}" =~ ^[0-9]+$ ]] && ICECAST_SAMPLE_RATE="${_ice_sr}" || ICECAST_SAMPLE_RATE=192000
  echo "[INFO] Icecast encoder sample rate: ${ICECAST_SAMPLE_RATE} Hz"
  prompt_helper _ice_bits "FLAC transport bit depth [16/24] (default 16): " 16 60
  if [[ "${_ice_bits}" =~ ^(16|24)$ ]]; then
    ICECAST_BIT_DEPTH="${_ice_bits}"
  else
    [ -n "${_ice_bits}" ] && echo "[INFO] Invalid bit depth '${_ice_bits}', defaulting to 16"
    ICECAST_BIT_DEPTH="16"
  fi
  echo "[INFO] Icecast FLAC transport bit depth: ${ICECAST_BIT_DEPTH}-bit"
  ICECAST_CODEC="flac"
  if [ -z "${ICECAST_MOUNT:-}" ]; then
    ICECAST_MOUNT="/mpx"
  fi
  echo "[INFO] Icecast codec fixed to FLAC-in-Ogg for broad player compatibility (${ICECAST_MOUNT})"

  echo "[INFO] MPX capture endpoints consumed by mpx-mix (read/capture side of ST's MPX output loopbacks):"
  prompt_helper _st_p1 "Program 1 MPX capture device (default ompx_prg1mpx_cap): " ompx_prg1mpx_cap 60
  ST_OUT_P1="${_st_p1:-ompx_prg1mpx_cap}"
  prompt_helper _st_p2 "Program 2 MPX capture device (default ompx_prg2mpx_cap, 'none' to disable): " ompx_prg2mpx_cap 60
  [ "${_st_p2,,}" = "none" ] && ST_OUT_P2="" || ST_OUT_P2="${_st_p2:-ompx_prg2mpx_cap}"
}

configure_rds_dialog(){
  local _rds_mode_default="U"
  local _rds2_mode_default="U"
  echo ""
  echo "=== RDS sync configuration ==="
  echo "  Syncs RadioText from a text URL OR from stream metadata"
  echo "  Program 1 output file: ${OMPX_HOME}/rds/prog1/rt.txt"
  echo "  Program 1 sidecar: ${OMPX_HOME}/rds/prog1/rds-info.json"
  prompt_helper _rds_enable "Enable Program 1 RDS text sync? [y/N] (default N): " N 60
  _rds_enable=${_rds_enable^^}
  if [ "${_rds_enable}" != "Y" ]; then
    RDS_PROG1_ENABLE="false"
    RDS_PROG1_SOURCE="url"
    RDS_PROG1_RT_URL=""
    echo "[INFO] Program 1 RDS sync disabled"
  else
    RDS_PROG1_ENABLE="true"
    [ "${RDS_PROG1_SOURCE}" = "metadata" ] && _rds_mode_default="M"
    [ "${RDS_PROG1_SOURCE}" = "icecast" ]  && _rds_mode_default="I"
    prompt_helper _rds_mode "Program 1 RDS source [U=url/M=metadata/I=icecast] (default ${_rds_mode_default}): " "${_rds_mode_default}" 60
    _rds_mode=${_rds_mode^^}
    if [ "${_rds_mode}" = "M" ]; then
      RDS_PROG1_SOURCE="metadata"
      RDS_PROG1_RT_URL=""
      RDS_PROG1_ICECAST_STATS_URL=""
      RDS_PROG1_ICECAST_MOUNT=""
      if is_placeholder_stream_url "${RADIO1_URL}"; then
        echo "[WARNING] Program 1 stream URL is placeholder/empty; metadata sync may fail until RADIO1_URL is set"
      fi
      echo "[INFO] Program 1 metadata mode enabled (reads StreamTitle from RADIO1_URL)"
    elif [ "${_rds_mode}" = "I" ]; then
      RDS_PROG1_SOURCE="icecast"
      RDS_PROG1_RT_URL=""
      # Auto-derive stats URL and mount from RADIO1_URL as defaults
      _p1_auto_stats="" ; _p1_auto_mount=""
      if [ -n "${RADIO1_URL}" ]; then
        _p1_no_scheme="${RADIO1_URL#*://}"
        _p1_host_port="${_p1_no_scheme%%/*}"
        _p1_auto_mount="/${_p1_no_scheme#*/}"
        _p1_auto_stats="http://${_p1_host_port}/status-json.xsl"
      fi
      _p1_stats_default="${RDS_PROG1_ICECAST_STATS_URL:-${_p1_auto_stats}}"
      _p1_mount_default="${RDS_PROG1_ICECAST_MOUNT:-${_p1_auto_mount}}"
      prompt_helper _p1_stats_in "Icecast stats JSON URL for Program 1 (default ${_p1_stats_default}): " "${_p1_stats_default}" 180
      [ -z "${_p1_stats_in}" ] && _p1_stats_in="${_p1_stats_default}"
      prompt_helper _p1_mount_in "Icecast mount point for Program 1 (default ${_p1_mount_default}): " "${_p1_mount_default}" 60
      [ -z "${_p1_mount_in}" ] && _p1_mount_in="${_p1_mount_default}"
      if [ -z "${_p1_stats_in}" ] || [ -z "${_p1_mount_in}" ]; then
        echo "[WARNING] Icecast stats URL or mount empty; disabling Program 1 RDS sync"
        RDS_PROG1_ENABLE="false"
        RDS_PROG1_ICECAST_STATS_URL=""
        RDS_PROG1_ICECAST_MOUNT=""
      else
        RDS_PROG1_ICECAST_STATS_URL="${_p1_stats_in}"
        RDS_PROG1_ICECAST_MOUNT="${_p1_mount_in}"
        echo "[INFO] Program 1 Icecast stats mode: ${RDS_PROG1_ICECAST_STATS_URL} mount ${RDS_PROG1_ICECAST_MOUNT}"
      fi
    else
      RDS_PROG1_SOURCE="url"
      RDS_PROG1_ICECAST_STATS_URL=""
      RDS_PROG1_ICECAST_MOUNT=""
      prompt_helper _rds_url "RDS text URL for Program 1: " "" 180
      if [ -z "${_rds_url}" ]; then
        echo "[WARNING] Empty RDS URL; disabling Program 1 RDS sync"
        RDS_PROG1_ENABLE="false"
        RDS_PROG1_RT_URL=""
      else
        RDS_PROG1_RT_URL="${_rds_url}"
      fi
    fi

    if [ "${RDS_PROG1_ENABLE}" = "true" ]; then
      prompt_helper _rds_int "Refresh interval seconds (default ${RDS_PROG1_INTERVAL_SEC}): " "" 60
      if [[ "${_rds_int}" =~ ^[0-9]+$ ]] && [ "${_rds_int}" -ge 1 ]; then
        RDS_PROG1_INTERVAL_SEC="${_rds_int}"
      fi

      prompt_helper _rds1_ps "Program 1 RDS PS (max 8 chars, default ${RDS_PROG1_PS}): " "" 60
      [ -n "${_rds1_ps}" ] && RDS_PROG1_PS="${_rds1_ps:0:8}"
      prompt_helper _rds1_pi "Program 1 RDS PI hex (4 chars, default ${RDS_PROG1_PI}): " "" 60
      if [ -n "${_rds1_pi}" ] && [[ "${_rds1_pi^^}" =~ ^[0-9A-F]{4}$ ]]; then
        RDS_PROG1_PI="${_rds1_pi^^}"
      fi
      prompt_helper _rds1_pty "Program 1 RDS PTY (0-31, default ${RDS_PROG1_PTY}): " "" 60
      if [ -n "${_rds1_pty}" ] && [[ "${_rds1_pty}" =~ ^[0-9]+$ ]] && [ "${_rds1_pty}" -ge 0 ] && [ "${_rds1_pty}" -le 31 ]; then
        RDS_PROG1_PTY="${_rds1_pty}"
      fi
      prompt_helper _rds1_tp "Program 1 TP flag [y/N] (default $( [ "${RDS_PROG1_TP}" = "true" ] && echo Y || echo N )): " "" 60
      [ "${_rds1_tp^^}" = "Y" ] && RDS_PROG1_TP="true"
      [ "${_rds1_tp^^}" = "N" ] && RDS_PROG1_TP="false"
      prompt_helper _rds1_ta "Program 1 TA flag [y/N] (default $( [ "${RDS_PROG1_TA}" = "true" ] && echo Y || echo N )): " "" 60
      [ "${_rds1_ta^^}" = "Y" ] && RDS_PROG1_TA="true"
      [ "${_rds1_ta^^}" = "N" ] && RDS_PROG1_TA="false"
      prompt_helper _rds1_ms "Program 1 MS flag [y/N] (default $( [ "${RDS_PROG1_MS}" = "true" ] && echo Y || echo N )): " "" 60
      [ "${_rds1_ms^^}" = "Y" ] && RDS_PROG1_MS="true"
      [ "${_rds1_ms^^}" = "N" ] && RDS_PROG1_MS="false"
      prompt_helper _rds1_ct "Program 1 include clock-time (CT) in sidecar output? [Y/n] (default $( [ "${RDS_PROG1_CT_ENABLE}" = "true" ] && echo Y || echo N )): " "" 60
      [ "${_rds1_ct^^}" = "Y" ] && RDS_PROG1_CT_ENABLE="true"
      [ "${_rds1_ct^^}" = "N" ] && RDS_PROG1_CT_ENABLE="false"
      if [ "${RDS_PROG1_CT_ENABLE}" = "true" ]; then
        prompt_helper _rds1_ct_mode "Program 1 CT mode [L=local/U=UTC] (default $( [ "${RDS_PROG1_CT_MODE}" = "utc" ] && echo U || echo L )): " "" 60
        [ "${_rds1_ct_mode^^}" = "U" ] && RDS_PROG1_CT_MODE="utc"
        [ "${_rds1_ct_mode^^}" = "L" ] && RDS_PROG1_CT_MODE="local"
      fi

      RDS_PROG1_RT_PATH="${OMPX_HOME}/rds/prog1/rt.txt"
      RDS_PROG1_INFO_PATH="${OMPX_HOME}/rds/prog1/rds-info.json"
      if [ "${RDS_PROG1_SOURCE}" = "metadata" ]; then
        echo "[INFO] Program 1 RDS sync enabled (metadata): RADIO1_URL -> ${RDS_PROG1_RT_PATH} every ${RDS_PROG1_INTERVAL_SEC}s"
      elif [ "${RDS_PROG1_SOURCE}" = "icecast" ]; then
        echo "[INFO] Program 1 RDS sync enabled (icecast): ${RDS_PROG1_ICECAST_STATS_URL} -> ${RDS_PROG1_RT_PATH} every ${RDS_PROG1_INTERVAL_SEC}s"
      else
        echo "[INFO] Program 1 RDS sync enabled (url): ${RDS_PROG1_RT_URL} -> ${RDS_PROG1_RT_PATH} every ${RDS_PROG1_INTERVAL_SEC}s"
      fi
      echo "[INFO] Program 1 RDS sidecar JSON: ${RDS_PROG1_INFO_PATH}"
    fi
  fi

  echo ""
  echo "  Program 2 output file: ${OMPX_HOME}/rds/prog2/rt.txt"
  echo "  Program 2 sidecar: ${OMPX_HOME}/rds/prog2/rds-info.json"
  prompt_helper _rds2_enable "Enable Program 2 RDS text sync? [y/N] (default N): " N 60
  _rds2_enable=${_rds2_enable^^}
  if [ "${_rds2_enable}" != "Y" ]; then
    RDS_PROG2_ENABLE="false"
    RDS_PROG2_SOURCE="url"
    RDS_PROG2_RT_URL=""
    echo "[INFO] Program 2 RDS sync disabled"
  else
    RDS_PROG2_ENABLE="true"
    [ "${RDS_PROG2_SOURCE}" = "metadata" ] && _rds2_mode_default="M"
    [ "${RDS_PROG2_SOURCE}" = "icecast" ]  && _rds2_mode_default="I"
    prompt_helper _rds2_mode "Program 2 RDS source [U=url/M=metadata/I=icecast] (default ${_rds2_mode_default}): " "${_rds2_mode_default}" 60
    _rds2_mode=${_rds2_mode^^}
    if [ "${_rds2_mode}" = "M" ]; then
      RDS_PROG2_SOURCE="metadata"
      RDS_PROG2_RT_URL=""
      RDS_PROG2_ICECAST_STATS_URL=""
      RDS_PROG2_ICECAST_MOUNT=""
      if is_placeholder_stream_url "${RADIO2_URL}"; then
        echo "[WARNING] Program 2 stream URL is placeholder/empty; metadata sync may fail until RADIO2_URL is set"
      fi
      echo "[INFO] Program 2 metadata mode enabled (reads StreamTitle from RADIO2_URL)"
    elif [ "${_rds2_mode}" = "I" ]; then
      RDS_PROG2_SOURCE="icecast"
      RDS_PROG2_RT_URL=""
      # Auto-derive stats URL and mount from RADIO2_URL as defaults
      _p2_auto_stats="" ; _p2_auto_mount=""
      if [ -n "${RADIO2_URL}" ]; then
        _p2_no_scheme="${RADIO2_URL#*://}"
        _p2_host_port="${_p2_no_scheme%%/*}"
        _p2_auto_mount="/${_p2_no_scheme#*/}"
        _p2_auto_stats="http://${_p2_host_port}/status-json.xsl"
      fi
      _p2_stats_default="${RDS_PROG2_ICECAST_STATS_URL:-${_p2_auto_stats}}"
      _p2_mount_default="${RDS_PROG2_ICECAST_MOUNT:-${_p2_auto_mount}}"
      prompt_helper _p2_stats_in "Icecast stats JSON URL for Program 2 (default ${_p2_stats_default}): " "${_p2_stats_default}" 180
      [ -z "${_p2_stats_in}" ] && _p2_stats_in="${_p2_stats_default}"
      prompt_helper _p2_mount_in "Icecast mount point for Program 2 (default ${_p2_mount_default}): " "${_p2_mount_default}" 60
      [ -z "${_p2_mount_in}" ] && _p2_mount_in="${_p2_mount_default}"
      if [ -z "${_p2_stats_in}" ] || [ -z "${_p2_mount_in}" ]; then
        echo "[WARNING] Icecast stats URL or mount empty; disabling Program 2 RDS sync"
        RDS_PROG2_ENABLE="false"
        RDS_PROG2_ICECAST_STATS_URL=""
        RDS_PROG2_ICECAST_MOUNT=""
      else
        RDS_PROG2_ICECAST_STATS_URL="${_p2_stats_in}"
        RDS_PROG2_ICECAST_MOUNT="${_p2_mount_in}"
        echo "[INFO] Program 2 Icecast stats mode: ${RDS_PROG2_ICECAST_STATS_URL} mount ${RDS_PROG2_ICECAST_MOUNT}"
      fi
    else
      RDS_PROG2_SOURCE="url"
      RDS_PROG2_ICECAST_STATS_URL=""
      RDS_PROG2_ICECAST_MOUNT=""
      prompt_helper _rds2_url "RDS text URL for Program 2: " "" 180
      if [ -z "${_rds2_url}" ]; then
        echo "[WARNING] Empty RDS URL; disabling Program 2 RDS sync"
        RDS_PROG2_ENABLE="false"
        RDS_PROG2_RT_URL=""
      else
        RDS_PROG2_RT_URL="${_rds2_url}"
      fi
    fi

    if [ "${RDS_PROG2_ENABLE}" = "true" ]; then
      prompt_helper _rds2_int "Refresh interval seconds (default ${RDS_PROG2_INTERVAL_SEC}): " "" 60
      if [[ "${_rds2_int}" =~ ^[0-9]+$ ]] && [ "${_rds2_int}" -ge 1 ]; then
        RDS_PROG2_INTERVAL_SEC="${_rds2_int}"
      fi

      prompt_helper _rds2_ps "Program 2 RDS PS (max 8 chars, default ${RDS_PROG2_PS}): " "" 60
      [ -n "${_rds2_ps}" ] && RDS_PROG2_PS="${_rds2_ps:0:8}"
      prompt_helper _rds2_pi "Program 2 RDS PI hex (4 chars, default ${RDS_PROG2_PI}): " "" 60
      if [ -n "${_rds2_pi}" ] && [[ "${_rds2_pi^^}" =~ ^[0-9A-F]{4}$ ]]; then
        RDS_PROG2_PI="${_rds2_pi^^}"
      fi
      prompt_helper _rds2_pty "Program 2 RDS PTY (0-31, default ${RDS_PROG2_PTY}): " "" 60
      if [ -n "${_rds2_pty}" ] && [[ "${_rds2_pty}" =~ ^[0-9]+$ ]] && [ "${_rds2_pty}" -ge 0 ] && [ "${_rds2_pty}" -le 31 ]; then
        RDS_PROG2_PTY="${_rds2_pty}"
      fi
      prompt_helper _rds2_tp "Program 2 TP flag [y/N] (default $( [ "${RDS_PROG2_TP}" = "true" ] && echo Y || echo N )): " "" 60
      [ "${_rds2_tp^^}" = "Y" ] && RDS_PROG2_TP="true"
      [ "${_rds2_tp^^}" = "N" ] && RDS_PROG2_TP="false"
      prompt_helper _rds2_ta "Program 2 TA flag [y/N] (default $( [ "${RDS_PROG2_TA}" = "true" ] && echo Y || echo N )): " "" 60
      [ "${_rds2_ta^^}" = "Y" ] && RDS_PROG2_TA="true"
      [ "${_rds2_ta^^}" = "N" ] && RDS_PROG2_TA="false"
      prompt_helper _rds2_ms "Program 2 MS flag [y/N] (default $( [ "${RDS_PROG2_MS}" = "true" ] && echo Y || echo N )): " "" 60
      [ "${_rds2_ms^^}" = "Y" ] && RDS_PROG2_MS="true"
      [ "${_rds2_ms^^}" = "N" ] && RDS_PROG2_MS="false"
      prompt_helper _rds2_ct "Program 2 include clock-time (CT) in sidecar output? [Y/n] (default $( [ "${RDS_PROG2_CT_ENABLE}" = "true" ] && echo Y || echo N )): " "" 60
      [ "${_rds2_ct^^}" = "Y" ] && RDS_PROG2_CT_ENABLE="true"
      [ "${_rds2_ct^^}" = "N" ] && RDS_PROG2_CT_ENABLE="false"
      if [ "${RDS_PROG2_CT_ENABLE}" = "true" ]; then
        prompt_helper _rds2_ct_mode "Program 2 CT mode [L=local/U=UTC] (default $( [ "${RDS_PROG2_CT_MODE}" = "utc" ] && echo U || echo L )): " "" 60
        [ "${_rds2_ct_mode^^}" = "U" ] && RDS_PROG2_CT_MODE="utc"
        [ "${_rds2_ct_mode^^}" = "L" ] && RDS_PROG2_CT_MODE="local"
      fi

      RDS_PROG2_RT_PATH="${OMPX_HOME}/rds/prog2/rt.txt"
      RDS_PROG2_INFO_PATH="${OMPX_HOME}/rds/prog2/rds-info.json"
      if [ "${RDS_PROG2_SOURCE}" = "metadata" ]; then
        echo "[INFO] Program 2 RDS sync enabled (metadata): RADIO2_URL -> ${RDS_PROG2_RT_PATH} every ${RDS_PROG2_INTERVAL_SEC}s"
      elif [ "${RDS_PROG2_SOURCE}" = "icecast" ]; then
        echo "[INFO] Program 2 RDS sync enabled (icecast): ${RDS_PROG2_ICECAST_STATS_URL} -> ${RDS_PROG2_RT_PATH} every ${RDS_PROG2_INTERVAL_SEC}s"
      else
        echo "[INFO] Program 2 RDS sync enabled (url): ${RDS_PROG2_RT_URL} -> ${RDS_PROG2_RT_PATH} every ${RDS_PROG2_INTERVAL_SEC}s"
      fi
      echo "[INFO] Program 2 RDS sidecar JSON: ${RDS_PROG2_INFO_PATH}"
    fi
  fi
}

install_icecast_local(){
  echo "[INFO] Installing icecast2..."
  DEBIAN_FRONTEND=noninteractive apt install -y icecast2 || { echo "[WARNING] icecast2 install failed"; return 1; }
  local admin_pass="${_ICE_ADMIN_PASS:-admin}"
  local source_user="${ICECAST_SOURCE_USER:-source}"
  local source_pass="${ICECAST_PASSWORD:-}"
  if [ -z "${source_pass}" ]; then
    source_pass="$(generate_secure_password 24)"
    ICECAST_PASSWORD="${source_pass}"
    echo "[INFO] Generated Icecast source password for local install"
  fi
  local admin_user="${ICECAST_ADMIN_USER:-admin}"
  local port="${ICECAST_PORT:-8000}"
  local max_clients="${_ICE_MAX_LISTENERS:-25}"
  local station="${_ICE_STATION:-oMPX}"
  cat > /etc/icecast2/icecast.xml << ICEXML
<icecast>
  <limits>
    <clients>${max_clients}</clients><sources>4</sources><threadpool>5</threadpool>
    <queue-size>524288</queue-size><client-timeout>30</client-timeout>
    <header-timeout>15</header-timeout><source-timeout>10</source-timeout>
    <burst-on-connect>1</burst-on-connect><burst-size>65535</burst-size>
  </limits>
  <authentication>
    <source-password>${source_pass}</source-password>
    <relay-password>${source_pass}</relay-password>
    <admin-user>${admin_user}</admin-user>
    <admin-password>${admin_pass}</admin-password>
  </authentication>
  <hostname>localhost</hostname>
  <listen-socket><port>${port}</port></listen-socket>
  <http-headers>
    <header name="Access-Control-Allow-Origin" value="*" />
  </http-headers>
  <mount type="normal">
    <mount-name>${ICECAST_MOUNT}</mount-name>
    <stream-name>${station}</stream-name>
    <stream-description>192kHz FLAC stereo MPX - oMPX</stream-description>
    <max-listeners>${max_clients}</max-listeners>
    <public>0</public>
  </mount>
  <fileserve>1</fileserve>
  <paths>
    <basedir>/usr/share/icecast2</basedir><logdir>/var/log/icecast2</logdir>
    <webroot>/usr/share/icecast2/web</webroot><adminroot>/usr/share/icecast2/admin</adminroot>
    <pidfile>/run/icecast2/icecast2.pid</pidfile>
  </paths>
  <logging><accesslog>access.log</accesslog><errorlog>error.log</errorlog><loglevel>3</loglevel></logging>
  <security><chroot>0</chroot></security>
</icecast>
ICEXML
  chmod 640 /etc/icecast2/icecast.xml
  chown root:icecast /etc/icecast2/icecast.xml 2>/dev/null || chown root:root /etc/icecast2/icecast.xml
  sed -i 's/^ENABLE=.*/ENABLE=true/' /etc/default/icecast2 2>/dev/null || true
  systemctl daemon-reload || true
  systemctl enable icecast2 || true
  systemctl restart icecast2 || true
  echo "[SUCCESS] icecast2 running on port ${port}, mount ${ICECAST_MOUNT}, source user ${source_user}"
}

remove_stereo_tool_enterprise_service(){
  if has_systemd; then
    systemctl disable --now stereo-tool-enterprise.service >/dev/null 2>&1 || true
  fi
  rm -f "${STEREO_TOOL_ENTERPRISE_SERVICE}" "${STEREO_TOOL_ENTERPRISE_LAUNCHER}" || true
}

prompt_stereo_tool_limit_preset(){
  local cfg_st_limit=""
  local cfg_st_interval=""
  local cfg_st_burst=""
  echo "  Start-limit presets (when repeated crashes happen):"
  echo "    S) Strict   - 5 failures in 60s, then stop retrying"
  echo "    B) Balanced - 10 failures in 60s, then stop retrying"
  echo "    L) Lenient  - 20 failures in 120s, then stop retrying"
  echo "    C) Custom   - set your own window and failure count"
  read -t 60 -p "Choose Stereo Tool crash-limit preset [S/B/L/C] (default B): " cfg_st_limit || cfg_st_limit="B"
  cfg_st_limit=${cfg_st_limit^^}
  case "${cfg_st_limit}" in
    S)
      STEREO_TOOL_START_LIMIT_PRESET="strict"
      ;;
    L)
      STEREO_TOOL_START_LIMIT_PRESET="lenient"
      ;;
    C)
      STEREO_TOOL_START_LIMIT_PRESET="custom"
      read -t 60 -p "Custom start-limit interval (seconds, default ${STEREO_TOOL_START_LIMIT_INTERVAL_SEC}): " cfg_st_interval || cfg_st_interval=""
      read -t 60 -p "Custom start-limit burst (failures, default ${STEREO_TOOL_START_LIMIT_BURST}): " cfg_st_burst || cfg_st_burst=""
      if [[ "${cfg_st_interval}" =~ ^[0-9]+$ ]] && [ "${cfg_st_interval}" -gt 0 ]; then
        STEREO_TOOL_START_LIMIT_INTERVAL_SEC="${cfg_st_interval}"
      fi
      if [[ "${cfg_st_burst}" =~ ^[0-9]+$ ]] && [ "${cfg_st_burst}" -gt 0 ]; then
        STEREO_TOOL_START_LIMIT_BURST="${cfg_st_burst}"
      fi
      ;;
    *)
      STEREO_TOOL_START_LIMIT_PRESET="balanced"
      ;;
  esac
}

prompt_stereo_tool_web_binding(){
  local cfg_st_bind=""
  local cfg_st_port=""
  local cfg_st_whitelist=""

  echo "  Stereo Tool web bind configuration:"
  echo "    Current bind address : ${STEREO_TOOL_WEB_BIND}"
  echo "    Current web port     : ${STEREO_TOOL_WEB_PORT}"
  echo "    Current whitelist    : ${STEREO_TOOL_WEB_WHITELIST}"

  read -t 60 -p "Bind address (IP/host, default ${STEREO_TOOL_WEB_BIND}): " cfg_st_bind || cfg_st_bind=""
  if [ -n "${cfg_st_bind}" ]; then
    STEREO_TOOL_WEB_BIND="${cfg_st_bind}"
  fi

  read -t 60 -p "Web port (1-65535, default ${STEREO_TOOL_WEB_PORT}): " cfg_st_port || cfg_st_port=""
  if [ -n "${cfg_st_port}" ]; then
    if [[ "${cfg_st_port}" =~ ^[0-9]+$ ]] && [ "${cfg_st_port}" -ge 1 ] && [ "${cfg_st_port}" -le 65535 ]; then
      STEREO_TOOL_WEB_PORT="${cfg_st_port}"
    else
      echo "[WARNING] Invalid port '${cfg_st_port}', keeping ${STEREO_TOOL_WEB_PORT}"
    fi
  fi

  read -t 60 -p "CIDR whitelist (default ${STEREO_TOOL_WEB_WHITELIST}): " cfg_st_whitelist || cfg_st_whitelist=""
  if [ -n "${cfg_st_whitelist}" ]; then
    STEREO_TOOL_WEB_WHITELIST="${cfg_st_whitelist}"
  fi

  echo "[INFO] Stereo Tool web endpoint configured: bind=${STEREO_TOOL_WEB_BIND}, port=${STEREO_TOOL_WEB_PORT}, whitelist=${STEREO_TOOL_WEB_WHITELIST}"
}

prompt_ompx_web_ui_binding(){
  local cfg_web_enable=""
  local cfg_web_bind=""
  local cfg_web_port=""
  local cfg_web_whitelist=""
  local cfg_web_auth=""
  local cfg_web_user=""
  local cfg_web_pass=""

  echo ""
  echo "oMPX web control UI (live patch preview + waveform/spectrum):"
  prompt_helper cfg_web_enable "Enable oMPX web UI? [Y/n] (default Y): " Y 60
  cfg_web_enable=${cfg_web_enable^^}
  if [ "${cfg_web_enable}" = "N" ]; then
    OMPX_WEB_UI_ENABLE="false"
    echo "[INFO] oMPX web UI disabled"
    return
  fi
  OMPX_WEB_UI_ENABLE="true"

  echo "  Current bind address : ${OMPX_WEB_BIND}"
  echo "  Current web port     : ${OMPX_WEB_PORT}"
  echo "  Current whitelist    : ${OMPX_WEB_WHITELIST}"

  prompt_helper cfg_web_bind "Bind address (IP/host, default ${OMPX_WEB_BIND}): " "${OMPX_WEB_BIND}" 60
  if [ -n "${cfg_web_bind}" ]; then
    OMPX_WEB_BIND="${cfg_web_bind}"
  fi

  prompt_helper cfg_web_port "Web port (1-65535, default ${OMPX_WEB_PORT}): " "${OMPX_WEB_PORT}" 60
  if [ -n "${cfg_web_port}" ]; then
    if [[ "${cfg_web_port}" =~ ^[0-9]+$ ]] && [ "${cfg_web_port}" -ge 1 ] && [ "${cfg_web_port}" -le 65535 ]; then
      OMPX_WEB_PORT="${cfg_web_port}"
    else
      echo "[WARNING] Invalid port '${cfg_web_port}', keeping ${OMPX_WEB_PORT}"
    fi
  fi

  prompt_helper cfg_web_whitelist "CIDR whitelist (default ${OMPX_WEB_WHITELIST}): " "${OMPX_WEB_WHITELIST}" 60
  if [ -n "${cfg_web_whitelist}" ]; then
    OMPX_WEB_WHITELIST="${cfg_web_whitelist}"
  fi

  prompt_helper cfg_web_auth "Enable login authentication for web UI? [y/N] (default N): " N 45
  cfg_web_auth=${cfg_web_auth^^}
  if [ "${cfg_web_auth}" = "Y" ]; then
    OMPX_WEB_AUTH_ENABLE="true"
    prompt_helper cfg_web_user "Web UI username (default ${OMPX_WEB_AUTH_USER}): " "${OMPX_WEB_AUTH_USER}" 60
    if [ -n "${cfg_web_user}" ]; then
      OMPX_WEB_AUTH_USER="${cfg_web_user}"
    fi
    prompt_helper cfg_web_pass "Web UI password (leave empty to auto-generate): " "" 60
    if [ -n "${cfg_web_pass}" ]; then
      OMPX_WEB_AUTH_PASSWORD="${cfg_web_pass}"
    else
      OMPX_WEB_AUTH_PASSWORD="$(generate_secure_password 24)"
      echo "[INFO] Generated web UI password for ${OMPX_WEB_AUTH_USER}: ${OMPX_WEB_AUTH_PASSWORD}"
    fi
  else
    OMPX_WEB_AUTH_ENABLE="false"
    OMPX_WEB_AUTH_PASSWORD=""
  fi

  echo "[INFO] oMPX web UI configured: bind=${OMPX_WEB_BIND}, port=${OMPX_WEB_PORT}, whitelist=${OMPX_WEB_WHITELIST}, auth=${OMPX_WEB_AUTH_ENABLE}"
}

has_chromium_binary(){
  command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1 || command -v google-chrome >/dev/null 2>&1
}

has_x11_runtime_tools(){
  command -v xset >/dev/null 2>&1 || command -v xdpyinfo >/dev/null 2>&1 || [ -d /tmp/.X11-unix ]
}

prompt_ompx_web_kiosk(){
  local cfg_kiosk_enable=""
  local cfg_kiosk_install=""
  local cfg_kiosk_display=""
  local cfg_kiosk_url=""
  local missing_components=""

  prompt_helper cfg_kiosk_enable "Enable local Chromium kiosk mode for oMPX UI (non-headless only)? [y/N] (default N): " N 45
  cfg_kiosk_enable=${cfg_kiosk_enable^^}
  if [ "${cfg_kiosk_enable}" != "Y" ]; then
    OMPX_WEB_KIOSK_ENABLE="false"
    return
  fi

  OMPX_WEB_KIOSK_ENABLE="true"
  OMPX_WEB_KIOSK_INSTALL_MISSING="false"

  if ! has_x11_runtime_tools; then
    missing_components="x11 ${missing_components}"
  fi
  if ! has_chromium_binary; then
    missing_components="chromium ${missing_components}"
  fi

  if [ -n "${missing_components}" ]; then
    echo "[INFO] Kiosk prerequisites missing: ${missing_components}"
    prompt_helper cfg_kiosk_install "Install and configure missing kiosk dependencies now? [Y/n] (default Y): " Y 45
    cfg_kiosk_install=${cfg_kiosk_install^^}
    if [ "${cfg_kiosk_install}" = "N" ]; then
      echo "[INFO] Skipping kiosk dependency installation by user choice; kiosk mode disabled"
      OMPX_WEB_KIOSK_ENABLE="false"
      OMPX_WEB_KIOSK_INSTALL_MISSING="false"
      return
    fi
    OMPX_WEB_KIOSK_INSTALL_MISSING="true"
  fi

  prompt_helper cfg_kiosk_display "X11 display for kiosk (default ${OMPX_WEB_KIOSK_DISPLAY}): " "${OMPX_WEB_KIOSK_DISPLAY}" 45
  if [ -n "${cfg_kiosk_display}" ]; then
    OMPX_WEB_KIOSK_DISPLAY="${cfg_kiosk_display}"
  fi
  prompt_helper cfg_kiosk_url "Kiosk URL (default ${OMPX_WEB_KIOSK_URL:-http://127.0.0.1:${OMPX_WEB_PORT}/}): " "${OMPX_WEB_KIOSK_URL:-http://127.0.0.1:${OMPX_WEB_PORT}/}" 60
  if [ -n "${cfg_kiosk_url}" ]; then
    OMPX_WEB_KIOSK_URL="${cfg_kiosk_url}"
  elif [ -z "${OMPX_WEB_KIOSK_URL}" ]; then
    OMPX_WEB_KIOSK_URL="http://127.0.0.1:${OMPX_WEB_PORT}/"
  fi

  echo "[INFO] oMPX kiosk mode configured: enabled=${OMPX_WEB_KIOSK_ENABLE}, display=${OMPX_WEB_KIOSK_DISPLAY}, url=${OMPX_WEB_KIOSK_URL}"

  # Prompt to start kiosk at boot
  local cfg_kiosk_boot=""
  prompt_helper cfg_kiosk_boot "Start oMPX kiosk mode automatically at boot? [Y/n] (default Y): " Y 45
  cfg_kiosk_boot=${cfg_kiosk_boot^^}
  if [ "${cfg_kiosk_boot}" = "N" ]; then
    if has_systemd; then
      systemctl disable ompx-web-kiosk.service 2>/dev/null || true
      echo "[INFO] oMPX kiosk systemd service will NOT start at boot."
    fi
  else
    if has_systemd; then
      systemctl enable ompx-web-kiosk.service 2>/dev/null || true
      echo "[INFO] oMPX kiosk systemd service will start at boot."
    fi
  fi
}

safe_apt_update(){
  DEBIAN_FRONTEND=noninteractive apt update -y || true
}

detect_loopback_card_ref(){
  local card_ref=""
  card_ref=$(aplay -l 2>/dev/null | awk '/\[Loopback\]/{gsub(":", "", $2); print $2; exit}')
  if [ -n "${card_ref}" ]; then
    echo "${card_ref}"
    return 0
  fi

  card_ref=$(awk -F'[][]' '/Loopback/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); split($1, a, /[[:space:]]+/); print a[1]; exit}' /proc/asound/cards 2>/dev/null)
  if [ -n "${card_ref}" ]; then
    echo "${card_ref}"
    return 0
  fi

  echo "Loopback"
}

render_asound_config(){
  # card_ref kept for caller compatibility but is no longer used; each loopback
  # card has its own ALSA name (loaded with id=<name>) so Stereo Tool can list
  # multiple distinct sinks instead of just substreams on one card.
  local enable_dsca="${ENABLE_DSCA_SINKS:-false}"
  local enable_preview="${ENABLE_PREVIEW_SINKS:-false}"
  local enable_program2="${PROGRAM2_ENABLED:-false}"
  local non_mpx_rate="${NON_MPX_SAMPLE_RATE:-48000}"
  local program2_input_block=""
  local program2_input_alias_block=""
  local program2_mpx_block=""
  local program2_mpx_alias_block=""
  local dsca_pcm_block=""
  local dsca_alias_block=""
  local preview_pcm_block=""
  local preview_alias_block=""

  if [ "${enable_program2}" = "true" ]; then
    program2_input_block=$(cat <<EOF
pcm.ompx_prg2in {
  type plug
  slave {
    pcm "hw:program2in,0"
    rate ${non_mpx_rate}
  }
  hint {
    show on
    description "oMPX Program 2 Input (write/playback)"
  }
}

pcm.ompx_prg2in_cap {
  type plug
  slave {
    pcm "hw:program2in,1"
    rate ${non_mpx_rate}
  }
  hint {
    show on
    description "oMPX Program 2 Input Capture (read/capture)"
  }
}

EOF
)

    program2_input_alias_block=$(cat <<'EOF'
pcm.ompx_program2_input {
  type plug
  slave.pcm "ompx_prg2in"
  hint {
    show on
    description "oMPX Program 2 Input (alias)"
  }
}

pcm.ompx_program2_input_capture {
  type plug
  slave.pcm "ompx_prg2in_cap"
  hint {
    show on
    description "oMPX Program 2 Input Capture (alias)"
  }
}

EOF
)

    program2_mpx_block=$(cat <<'EOF'
pcm.ompx_prg2mpx {
  type plug
  slave {
    pcm "hw:program2mpxsrc,0"
    channels 2
  }
  hint {
    show on
    description "oMPX Program 2 MPX Output"
  }
}

pcm.ompx_prg2mpx_cap {
  type plug
  slave {
    pcm "hw:program2mpxsrc,1"
    channels 2
  }
  hint {
    show on
    description "oMPX Program 2 MPX Output Capture (read/capture)"
  }
}

EOF
)

    program2_mpx_alias_block=$(cat <<'EOF'
pcm.ompx_program2_mpx_output {
  type plug
  slave.pcm "ompx_prg2mpx"
  hint {
    show on
    description "oMPX Program 2 MPX Output (alias)"
  }
}

pcm.ompx_program2_mpx_output_capture {
  type plug
  slave.pcm "ompx_prg2mpx_cap"
  hint {
    show on
    description "oMPX Program 2 MPX Output Capture (alias)"
  }
}

EOF
)
  fi

  if [ "${enable_preview}" = "true" ]; then
    preview_pcm_block=$(cat <<'EOF'
pcm.ompx_prg1prev {
  type plug
  slave {
    pcm "hw:program1preview,0"
    rate __NON_MPX_RATE__
  }
  hint {
    show on
    description "oMPX Program 1 Preview (write/playback)"
  }
}

pcm.ompx_prg1prev_cap {
  type plug
  slave {
    pcm "hw:program1preview,1"
    rate __NON_MPX_RATE__
  }
  hint {
    show on
    description "oMPX Program 1 Preview Capture (read/capture)"
  }
}

EOF
)
    preview_pcm_block="${preview_pcm_block//__NON_MPX_RATE__/${non_mpx_rate}}"

    if [ "${enable_program2}" = "true" ]; then
      preview_pcm_block+=$'\n\npcm.ompx_prg2prev {\n  type plug\n  slave {\n    pcm "hw:program2preview,0"\n    rate '
      preview_pcm_block+="${non_mpx_rate}"
      preview_pcm_block+=$'\n  }\n  hint {\n    show on\n    description "oMPX Program 2 Preview (write/playback)"\n  }\n}\n\npcm.ompx_prg2prev_cap {\n  type plug\n  slave {\n    pcm "hw:program2preview,1"\n    rate '
      preview_pcm_block+="${non_mpx_rate}"
      preview_pcm_block+=$'\n  }\n  hint {\n    show on\n    description "oMPX Program 2 Preview Capture (read/capture)"\n  }\n}\n'
    fi

    preview_alias_block=$(cat <<'EOF'
pcm.ompx_program1_preview {
  type plug
  slave.pcm "ompx_prg1prev"
  hint {
    show on
    description "oMPX Program 1 Preview (alias)"
  }
}

pcm.ompx_program1_preview_capture {
  type plug
  slave.pcm "ompx_prg1prev_cap"
  hint {
    show on
    description "oMPX Program 1 Preview Capture (alias)"
  }
}

EOF
)
    if [ "${enable_program2}" = "true" ]; then
      preview_alias_block+=$'\n\npcm.ompx_program2_preview {\n  type plug\n  slave.pcm "ompx_prg2prev"\n  hint {\n    show on\n    description "oMPX Program 2 Preview (alias)"\n  }\n}\n\npcm.ompx_program2_preview_capture {\n  type plug\n  slave.pcm "ompx_prg2prev_cap"\n  hint {\n    show on\n    description "oMPX Program 2 Preview Capture (alias)"\n  }\n}\n'
    fi
  fi

  if [ "${enable_dsca}" = "true" ]; then
    dsca_pcm_block=$(cat <<EOF
pcm.ompx_dsca_src {
  type plug
  slave {
    pcm "hw:dscasource,0"
    rate ${non_mpx_rate}
  }
  hint {
    show on
    description "oMPX DSCA Source (write/playback)"
  }
}

pcm.ompx_dsca_src_cap {
  type plug
  slave {
    pcm "hw:dscasource,1"
    rate ${non_mpx_rate}
  }
  hint {
    show on
    description "oMPX DSCA Source Capture (read/capture)"
  }
}

pcm.ompx_dsca_injection {
  type plug
  slave {
    pcm "hw:dscainjectionsr,0"
    rate ${non_mpx_rate}
  }
  hint {
    show on
    description "oMPX DSCA Injection"
  }
}

EOF
)

    dsca_alias_block=$(cat <<'EOF'
pcm.ompx_dsca_source {
  type plug
  slave.pcm "ompx_dsca_src"
  hint {
    show on
    description "oMPX DSCA Source (alias)"
  }
}

pcm.ompx_dsca_source_capture {
  type plug
  slave.pcm "ompx_dsca_src_cap"
  hint {
    show on
    description "oMPX DSCA Source Capture (alias)"
  }
}

EOF
)
  fi

  cat <<EOF
# BEGIN OMPX ALSA BLOCK
# oMPX ALSA virtual PCM map (auto-generated)

pcm.ompx_prg1in {
  type plug
  slave {
    pcm "hw:program1in,0"
    rate ${non_mpx_rate}
  }
  hint {
    show on
    description "oMPX Program 1 Input (write/playback)"
  }
}

pcm.ompx_prg1in_cap {
  type plug
  slave {
    pcm "hw:program1in,1"
    rate ${non_mpx_rate}
  }
  hint {
    show on
    description "oMPX Program 1 Input Capture (read/capture)"
  }
}

${program2_input_block}

${preview_pcm_block}

pcm.ompx_prg1mpx {
  type plug
  slave {
    pcm "hw:program1mpxsrc,0"
    channels 2
  }
  hint {
    show on
    description "oMPX Program 1 MPX Output"
  }
}

pcm.ompx_prg1mpx_cap {
  type plug
  slave {
    pcm "hw:program1mpxsrc,1"
    channels 2
  }
  hint {
    show on
    description "oMPX Program 1 MPX Output Capture (read/capture)"
  }
}

${program2_mpx_block}

${dsca_pcm_block}

pcm.ompx_mpx_to_icecast {
  type plug
  slave.pcm "hw:mpxmix,0"
  hint {
    show on
    description "oMPX MPX To Icecast"
  }
}

# Friendly alias layer (restored): readable names mapped to canonical ompx_prg* endpoints.
pcm.ompx_program1_input {
  type plug
  slave.pcm "ompx_prg1in"
  hint {
    show on
    description "oMPX Program 1 Input (alias)"
  }
}

pcm.ompx_program1_input_capture {
  type plug
  slave.pcm "ompx_prg1in_cap"
  hint {
    show on
    description "oMPX Program 1 Input Capture (alias)"
  }
}

${program2_input_alias_block}

${preview_alias_block}

pcm.ompx_program1_mpx_output {
  type plug
  slave.pcm "ompx_prg1mpx"
  hint {
    show on
    description "oMPX Program 1 MPX Output (alias)"
  }
}

pcm.ompx_program1_mpx_output_capture {
  type plug
  slave.pcm "ompx_prg1mpx_cap"
  hint {
    show on
    description "oMPX Program 1 MPX Output Capture (alias)"
  }
}

${program2_mpx_alias_block}

${dsca_alias_block}

# END OMPX ALSA BLOCK

EOF
}

write_profile_file(){
  local old_radio1=""
  local old_radio2=""
  local _tmp_old=""
  ICECAST_CODEC="flac"
  echo "[INFO] Creating user profile configuration..."
  mkdir -p "${OMPX_HOME}"
  PROFILE="${OMPX_HOME}/.profile"

  if [ -f "${PROFILE}" ]; then
    _tmp_old=$(sed -n 's/^RADIO1_URL="\(.*\)"$/\1/p' "${PROFILE}" | head -n1 || true)
    old_radio1="${_tmp_old}"
    _tmp_old=$(sed -n 's/^RADIO2_URL="\(.*\)"$/\1/p' "${PROFILE}" | head -n1 || true)
    old_radio2="${_tmp_old}"
  fi

  if [ "${ALLOW_PLACEHOLDER_STREAM_OVERWRITE}" != "true" ]; then
    if is_placeholder_stream_url "${RADIO1_URL}" && ! is_placeholder_stream_url "${old_radio1}"; then
      echo "[WARNING] Refusing to overwrite saved RADIO1_URL with a placeholder/empty value"
      RADIO1_URL="${old_radio1}"
    fi
    if is_placeholder_stream_url "${RADIO2_URL}" && ! is_placeholder_stream_url "${old_radio2}"; then
      echo "[WARNING] Refusing to overwrite saved RADIO2_URL with a placeholder/empty value"
      RADIO2_URL="${old_radio2}"
    fi
  fi

  cp -a "${PROFILE:-/dev/null}" "${PROFILE}.bak.$(date +%s)" 2>/dev/null || true
  cat > "$PROFILE" <<PROFILE_WRITTEN
# oMPX persistent environment (auto-generated)

RADIO1_URL="${RADIO1_URL}"
RADIO2_URL="${RADIO2_URL}"
STREAM_ENGINE="${STREAM_ENGINE}"
STREAM_SILENCE_MAX_DBFS="${STREAM_SILENCE_MAX_DBFS}"
INGEST_DELAY_SEC="${INGEST_DELAY_SEC}"
P1_INGEST_DELAY_SEC="${P1_INGEST_DELAY_SEC}"
P2_INGEST_DELAY_SEC="${P2_INGEST_DELAY_SEC}"
ICECAST_MODE="${ICECAST_MODE}"
ICECAST_HOST="${ICECAST_HOST}"
ICECAST_PORT="${ICECAST_PORT}"
ICECAST_SOURCE_USER="${ICECAST_SOURCE_USER}"
ICECAST_PASSWORD="${ICECAST_PASSWORD}"
ICECAST_ADMIN_USER="${ICECAST_ADMIN_USER}"
ICECAST_MOUNT="${ICECAST_MOUNT}"
ICECAST_SAMPLE_RATE="${ICECAST_SAMPLE_RATE}"
ICECAST_BIT_DEPTH="${ICECAST_BIT_DEPTH}"
ICECAST_CODEC="${ICECAST_CODEC}"
ICECAST_INPUT_MODE="${ICECAST_INPUT_MODE}"
ENABLE_DSCA_SINKS="${ENABLE_DSCA_SINKS}"
ENABLE_PREVIEW_SINKS="${ENABLE_PREVIEW_SINKS}"
NON_MPX_SAMPLE_RATE="${NON_MPX_SAMPLE_RATE}"
MODULES_DIR="${MODULES_DIR}"
MULTIBAND_PROFILE="${MULTIBAND_PROFILE}"
OMPX_STEREO_BACKEND="${OMPX_STEREO_BACKEND}"
OMPX_WRAPPER_RDS_ENABLE="${OMPX_WRAPPER_RDS_ENABLE}"
OMPX_WRAPPER_RDS_ENCODER_CMD="${OMPX_WRAPPER_RDS_ENCODER_CMD}"
OMPX_WRAPPER_SAMPLE_RATE="${OMPX_WRAPPER_SAMPLE_RATE}"
OMPX_WRAPPER_PILOT_LEVEL="${OMPX_WRAPPER_PILOT_LEVEL}"
OMPX_WRAPPER_RDS_LEVEL="${OMPX_WRAPPER_RDS_LEVEL}"
OMPX_WRAPPER_PRESET="${OMPX_WRAPPER_PRESET}"
OMPX_FM_PREEMPHASIS="${OMPX_FM_PREEMPHASIS}"
OMPX_WEB_UI_ENABLE="${OMPX_WEB_UI_ENABLE}"
OMPX_WEB_BIND="${OMPX_WEB_BIND}"
OMPX_WEB_PORT="${OMPX_WEB_PORT}"
OMPX_WEB_WHITELIST="${OMPX_WEB_WHITELIST}"
OMPX_WEB_AUTH_ENABLE="${OMPX_WEB_AUTH_ENABLE}"
OMPX_WEB_AUTH_USER="${OMPX_WEB_AUTH_USER}"
OMPX_WEB_AUTH_PASSWORD="${OMPX_WEB_AUTH_PASSWORD}"
OMPX_WEB_KIOSK_ENABLE="${OMPX_WEB_KIOSK_ENABLE}"
OMPX_WEB_KIOSK_DISPLAY="${OMPX_WEB_KIOSK_DISPLAY}"
OMPX_WEB_KIOSK_URL="${OMPX_WEB_KIOSK_URL}"
PROGRAM2_ENABLED="${PROGRAM2_ENABLED}"
ST_OUT_P1="${ST_OUT_P1}"
ST_OUT_P2="${ST_OUT_P2}"
RDS_PROG1_ENABLE="${RDS_PROG1_ENABLE}"
RDS_PROG1_SOURCE="${RDS_PROG1_SOURCE}"
RDS_PROG1_RT_URL="${RDS_PROG1_RT_URL}"
RDS_PROG1_ICECAST_STATS_URL="${RDS_PROG1_ICECAST_STATS_URL}"
RDS_PROG1_ICECAST_MOUNT="${RDS_PROG1_ICECAST_MOUNT}"
RDS_PROG1_INTERVAL_SEC="${RDS_PROG1_INTERVAL_SEC}"
RDS_PROG1_RT_PATH="${RDS_PROG1_RT_PATH}"
RDS_PROG1_PS="${RDS_PROG1_PS}"
RDS_PROG1_PI="${RDS_PROG1_PI}"
RDS_PROG1_PTY="${RDS_PROG1_PTY}"
RDS_PROG1_TP="${RDS_PROG1_TP}"
RDS_PROG1_TA="${RDS_PROG1_TA}"
RDS_PROG1_MS="${RDS_PROG1_MS}"
RDS_PROG1_CT_ENABLE="${RDS_PROG1_CT_ENABLE}"
RDS_PROG1_CT_MODE="${RDS_PROG1_CT_MODE}"
RDS_PROG1_INFO_PATH="${RDS_PROG1_INFO_PATH}"
RDS_PROG1_OVERRIDE_PATH="${RDS_PROG1_OVERRIDE_PATH}"
RDS_PROG2_ENABLE="${RDS_PROG2_ENABLE}"
RDS_PROG2_SOURCE="${RDS_PROG2_SOURCE}"
RDS_PROG2_RT_URL="${RDS_PROG2_RT_URL}"
RDS_PROG2_ICECAST_STATS_URL="${RDS_PROG2_ICECAST_STATS_URL}"
RDS_PROG2_ICECAST_MOUNT="${RDS_PROG2_ICECAST_MOUNT}"
RDS_PROG2_INTERVAL_SEC="${RDS_PROG2_INTERVAL_SEC}"
RDS_PROG2_RT_PATH="${RDS_PROG2_RT_PATH}"
RDS_PROG2_PS="${RDS_PROG2_PS}"
RDS_PROG2_PI="${RDS_PROG2_PI}"
RDS_PROG2_PTY="${RDS_PROG2_PTY}"
RDS_PROG2_TP="${RDS_PROG2_TP}"
RDS_PROG2_TA="${RDS_PROG2_TA}"
RDS_PROG2_MS="${RDS_PROG2_MS}"
RDS_PROG2_CT_ENABLE="${RDS_PROG2_CT_ENABLE}"
RDS_PROG2_CT_MODE="${RDS_PROG2_CT_MODE}"
RDS_PROG2_INFO_PATH="${RDS_PROG2_INFO_PATH}"
RDS_PROG2_OVERRIDE_PATH="${RDS_PROG2_OVERRIDE_PATH}"
PROFILE_WRITTEN
  chown "${OMPX_USER}:${OMPX_USER}" "$PROFILE"
  chmod 644 "$PROFILE"
  _log "Wrote profile ${PROFILE}."
  echo "[SUCCESS] Profile configuration created"
}

is_placeholder_stream_url(){
  local url="$1"
  [ -z "$url" ] && return 0
  [[ "$url" == *"example-icecast.local"* ]] && return 0
  [[ "$url" == *"your.stream/url"* ]] && return 0
  return 1
}

probe_stream_source(){
  local url="$1"
  local http_code=""
  local probe_output=""
  local max_volume=""
  local mean_volume=""
  local probe_attempt=1
  local probe_attempts=3
  local silent_attempts=0
  local silence_max_dbfs="${STREAM_SILENCE_MAX_DBFS:--85}"

  STREAM_CHECK_STATUS="ok"
  STREAM_CHECK_MESSAGE="stream responded with audio"

  if [[ "$url" =~ ^https?:// ]]; then
    http_code=$(curl -L -sS -o /dev/null --max-time 15 -w '%{http_code}' "$url" 2>/dev/null || echo "000")
    case "$http_code" in
      404)
        STREAM_CHECK_STATUS="http_404"
        STREAM_CHECK_MESSAGE="HTTP 404 Not Found"
        return 0
        ;;
      401|403)
        STREAM_CHECK_STATUS="http_auth"
        STREAM_CHECK_MESSAGE="HTTP ${http_code} returned by stream server"
        return 0
        ;;
      500|501|502|503|504|000)
        STREAM_CHECK_STATUS="offline"
        STREAM_CHECK_MESSAGE="HTTP/network probe failed with status ${http_code}"
        ;;
    esac
  fi

  while [ "${probe_attempt}" -le "${probe_attempts}" ]; do
    probe_output=$(timeout 20 ffmpeg -hide_banner -loglevel info -t 12 -i "$url" -map 0:a:0? -vn -sn -dn -af volumedetect -f null - 2>&1 || true)

    if printf '%s\n' "$probe_output" | grep -qiE '404 Not Found|Server returned 404|HTTP error 404'; then
      STREAM_CHECK_STATUS="http_404"
      STREAM_CHECK_MESSAGE="ffmpeg reported HTTP 404 Not Found"
      return 0
    fi
    if printf '%s\n' "$probe_output" | grep -qiE '403 Forbidden|401 Unauthorized'; then
      STREAM_CHECK_STATUS="http_auth"
      STREAM_CHECK_MESSAGE="ffmpeg reported an authorization error"
      return 0
    fi
    if printf '%s\n' "$probe_output" | grep -qiE 'Connection refused|timed out|Temporary failure|Name or service not known|No route to host|Failed to resolve|End of file'; then
      STREAM_CHECK_STATUS="offline"
      STREAM_CHECK_MESSAGE="stream appears unreachable or offline"
      return 0
    fi
    if printf '%s\n' "$probe_output" | grep -qiE 'matches no streams|does not contain any stream|Invalid data found when processing input'; then
      STREAM_CHECK_STATUS="no_audio"
      STREAM_CHECK_MESSAGE="stream did not present a usable audio stream"
      return 0
    fi
    if ! printf '%s\n' "$probe_output" | grep -q 'Audio:'; then
      STREAM_CHECK_STATUS="no_audio"
      STREAM_CHECK_MESSAGE="probe did not confirm an audio stream"
      return 0
    fi

    max_volume=$(printf '%s\n' "$probe_output" | awk -F': ' '/max_volume/ {print $2; exit}')
    mean_volume=$(printf '%s\n' "$probe_output" | awk -F': ' '/mean_volume/ {print $2; exit}')
    max_volume=${max_volume%% *}
    mean_volume=${mean_volume%% *}

    if [ -n "$max_volume" ] && [ -n "$mean_volume" ] && [ "$max_volume" = "-inf" ] && [ "$mean_volume" = "-inf" ]; then
      silent_attempts=$((silent_attempts + 1))
      probe_attempt=$((probe_attempt + 1))
      continue
    fi

    # Treat extremely low decoded audio as silence, but keep threshold configurable.
    if [ -n "$max_volume" ] && awk -v m="$max_volume" -v t="$silence_max_dbfs" 'BEGIN { exit !((m + 0) <= (t + 0)) }'; then
      silent_attempts=$((silent_attempts + 1))
      probe_attempt=$((probe_attempt + 1))
      continue
    fi

    break
  done

  if [ "${silent_attempts}" -ge "${probe_attempts}" ]; then
    STREAM_CHECK_STATUS="silent"
    STREAM_CHECK_MESSAGE="stream connected but decoded audio stayed below ${silence_max_dbfs} dBFS across ${probe_attempts} probe windows"
    return 0
  fi

  if [ -n "$http_code" ] && [ "$http_code" != "000" ]; then
    STREAM_CHECK_MESSAGE="stream responded with audio (HTTP ${http_code}, max_volume=${max_volume:-unknown}, mean_volume=${mean_volume:-unknown}, silent_windows=${silent_attempts}/${probe_attempts}, silence_threshold=${silence_max_dbfs}dBFS)"
  elif [ -n "$max_volume" ] || [ -n "$mean_volume" ]; then
    STREAM_CHECK_MESSAGE="stream responded with audio (max_volume=${max_volume:-unknown}, mean_volume=${mean_volume:-unknown}, silent_windows=${silent_attempts}/${probe_attempts}, silence_threshold=${silence_max_dbfs}dBFS)"
  fi
}

validate_stream_source_interactive(){
  local radio_num="$1"
  local var_name="$2"
  local url=""
  local choice=""
  local edited_url=""

  while true; do
    url="${!var_name:-}"
    if is_placeholder_stream_url "$url"; then
      echo "[INFO] RADIO${radio_num}_URL is empty/placeholder; skipping stream validation"
      return 0
    fi

    echo "[INFO] Validating RADIO${radio_num}_URL..."
    probe_stream_source "$url"
    if [ "$STREAM_CHECK_STATUS" = "ok" ]; then
      echo "[SUCCESS] RADIO${radio_num}_URL check passed: ${STREAM_CHECK_MESSAGE}"
      return 0
    fi

    echo "[WARNING] RADIO${radio_num}_URL check reported ${STREAM_CHECK_STATUS}: ${STREAM_CHECK_MESSAGE}"
    if [ -t 0 ]; then
      echo "[PROMPT] Stream validation for RADIO${radio_num}_URL needs a decision."
      echo "  R) Retry validation"
      echo "  E) Edit URL now"
      echo "  S) Skip this stream for now"
      echo "  C) Continue anyway"
      echo "  A) Abort installation"
      read -t 90 -p "Select [R/E/S/C/A] (default C): " choice || choice="C"
      choice=${choice^^}
      case "$choice" in
        R)
          continue
          ;;
        E)
          read -t 180 -p "Enter new RADIO${radio_num}_URL: " edited_url || edited_url=""
          if [ -n "$edited_url" ]; then
            printf -v "$var_name" '%s' "$edited_url"
          else
            echo "[INFO] URL unchanged"
          fi
          ;;
        S)
          printf -v "$var_name" '%s' ""
          echo "[INFO] RADIO${radio_num}_URL cleared; this stream will be skipped during install"
          return 0
          ;;
        A)
          echo "[ERROR] Aborting at user request due to stream validation failure"
          exit 1
          ;;
        *)
          echo "[INFO] Continuing installation with current RADIO${radio_num}_URL despite validation warning"
          return 0
          ;;
      esac
    else
      echo "[INFO] Non-interactive mode: continuing despite validation warning for RADIO${radio_num}_URL"
      return 0
    fi
  done
}

strip_old_ompx_sinks(){
  local in_file="$1"
  local out_file="$2"
  awk '
    BEGIN {
      split("ompx_prg1in ompx_prg1in_cap ompx_prg2in ompx_prg2in_cap ompx_prg1prev ompx_prg1prev_cap ompx_prg2prev ompx_prg2prev_cap ompx_prg1mpx ompx_prg1mpx_cap ompx_prg2mpx ompx_prg2mpx_cap ompx_dsca_src ompx_dsca_src_cap ompx_dsca_injection ompx_mpx_to_icecast ompx_program1_input ompx_program1_input_capture ompx_program2_input ompx_program2_input_capture ompx_program1_preview ompx_program1_preview_capture ompx_program2_preview ompx_program2_preview_capture ompx_program1_mpx_output ompx_program1_mpx_output_capture ompx_program2_mpx_output ompx_program2_mpx_output_capture ompx_dsca_source ompx_dsca_source_capture", a, " ")
      for (i in a) names[a[i]] = 1
      skip = 0
      depth = 0
      skip_marker = 0
    }
    {
      if ($0 ~ /^# BEGIN OMPX ALSA BLOCK/) {
        skip_marker = 1
        next
      }

      if (skip_marker == 1) {
        if ($0 ~ /^# END OMPX ALSA BLOCK/) {
          skip_marker = 0
        }
        next
      }

      if (skip == 1) {
        l1 = $0
        l2 = $0
        opens = gsub(/\{/, "{", l1)
        closes = gsub(/\}/, "}", l2)
        depth += opens - closes
        if (depth <= 0) {
          skip = 0
          depth = 0
        }
        next
      }

      if ($0 ~ /^[[:space:]]*(pcm|ctl)\.[[:alnum:]_]+[[:space:]]*\{/) {
        name = $0
        sub(/^[[:space:]]*(pcm|ctl)\./, "", name)
        sub(/[[:space:]]*\{.*/, "", name)
        if (name in names) {
          skip = 1
          depth = 1
          next
        }
      }

      print
    }
  ' "$in_file" > "$out_file"
}

strip_legacy_hw_references(){
  local in_file="$1"
  local out_file="$2"
  awk '
    BEGIN { skip = 0; depth = 0 }
    {
      if (skip == 1) {
        l1 = $0; l2 = $0
        opens = gsub(/\{/, "{", l1)
        closes = gsub(/\}/, "}", l2)
        depth += opens - closes
        if (depth <= 0) { skip = 0; depth = 0 }
        next
      }
      if ($0 ~ /^[[:space:]]*(pcm|ctl)\.[_a-zA-Z0-9]+[[:space:]]*\{/) {
        name = $0
        sub(/^[[:space:]]*(pcm|ctl)\./, "", name)
        sub(/[[:space:]]*\{.*/, "", name)
        if (match($0, /hw:[0-9]/)) {
          skip = 1
          depth = 1
          next
        }
      }
      print
    }
  ' "$in_file" > "$out_file"
}

load_ompx_aloop_profile(){
  local ompx_modprobe_conf="/etc/modprobe.d/70-ompx-snd-aloop.conf"
  local ompx_modules_load_conf="/etc/modules-load.d/70-ompx-snd-aloop.conf"
  local modprobe_opts=""
  local ids=()
  local enable_list=""
  local index_list=""
  local id_list=""
  local pcm_substreams_list=""
  local idx=10
  local id=""

  # Expose multiple named loopback cards so apps that do not enumerate ALSA
  # substreams (including some Stereo Tool builds) still show distinct sinks.
  ids=(program1in)
  if [ "${PROGRAM2_ENABLED}" = "true" ]; then
    ids+=(program2in)
  fi
  if [ "${ENABLE_PREVIEW_SINKS}" = "true" ]; then
    ids+=(program1preview)
    if [ "${PROGRAM2_ENABLED}" = "true" ]; then
      ids+=(program2preview)
    fi
  fi
  ids+=(program1mpxsrc)
  if [ "${PROGRAM2_ENABLED}" = "true" ]; then
    ids+=(program2mpxsrc)
  fi
  if [ "${ENABLE_DSCA_SINKS}" = "true" ]; then
    ids+=(dscasource dscainjectionsr)
  fi
  ids+=(mpxmix)

  if [ "${PROGRAM2_ENABLED}" = "true" ]; then
    if ! printf '%s\n' "${ids[@]}" | grep -qx 'program2in'; then
      echo "[ERROR] PROGRAM2_ENABLED=true but program2in card was not included in snd_aloop profile"
      return 1
    fi
    if ! printf '%s\n' "${ids[@]}" | grep -qx 'program2mpxsrc'; then
      echo "[ERROR] PROGRAM2_ENABLED=true but program2mpxsrc card was not included in snd_aloop profile"
      return 1
    fi
    if [ "${ENABLE_PREVIEW_SINKS}" = "true" ] && ! printf '%s\n' "${ids[@]}" | grep -qx 'program2preview'; then
      echo "[ERROR] PROGRAM2_ENABLED=true with preview enabled but program2preview card was not included"
      return 1
    fi
  fi

  for id in "${ids[@]}"; do
    if [ -n "${enable_list}" ]; then enable_list+=","; fi
    enable_list+="1"
    if [ -n "${index_list}" ]; then
      index_list+=","
    fi
    index_list+="${idx}"
    if [ -n "${id_list}" ]; then
      id_list+=","
    fi
    id_list+="${id}"
    if [ -n "${pcm_substreams_list}" ]; then
      pcm_substreams_list+=","
    fi
    pcm_substreams_list+="2"
    idx=$((idx + 1))
  done

  if [ -n "${id_list}" ]; then
    modprobe_opts="enable=${enable_list} index=${index_list} id=${id_list} pcm_substreams=${pcm_substreams_list}"
  fi

  cat > "${ompx_modprobe_conf}" <<EOF
options snd-aloop ${modprobe_opts}
EOF
  chmod 644 "${ompx_modprobe_conf}" || true

  cat > "${ompx_modules_load_conf}" <<'EOF'
snd-aloop
EOF
  chmod 644 "${ompx_modules_load_conf}" || true

  modprobe -r snd_aloop >/dev/null 2>&1 || true
  modprobe snd_aloop ${modprobe_opts}
}

if [ "${EUID}" -ne 0 ]; then
  echo "[ERROR] This script must be run as root"
  exit 1
fi

# Interactive confirmations for ALSA config behavior.
# Keep current defaults when running non-interactively.
if [ -t 0 ]; then
  echo ""
  echo "ALSA configuration options:"
  echo "  Y) Manage /etc/asound.conf during install"
  echo "  N) Skip asound.conf changes"
  read -t 30 -p "Manage ALSA config now? [Y/n] (default Y): " cfg_manage || cfg_manage="Y"
  cfg_manage=${cfg_manage^^}

  if [ "${cfg_manage}" = "N" ]; then
    CONFIG_SKIP=true
    echo "[INFO] CONFIG_SKIP=true (asound.conf changes disabled)"
  else
    CONFIG_SKIP=false
    if [ -f "${ASOUND_CONF_PATH}" ]; then
      read -t 30 -p "Overwrite ${ASOUND_CONF_PATH}? [Y/n] (default Y): " cfg_overwrite || cfg_overwrite="Y"
      cfg_overwrite=${cfg_overwrite^^}
      if [ "${cfg_overwrite}" = "N" ]; then
        CONFIG_OVERWRITE=false
        echo "[INFO] CONFIG_OVERWRITE=false (keeping existing asound.conf)"
      else
        CONFIG_OVERWRITE=true
        read -t 30 -p "Backup existing asound.conf first? [Y/n] (default Y): " cfg_backup || cfg_backup="Y"
        cfg_backup=${cfg_backup^^}
        if [ "${cfg_backup}" = "N" ]; then
          CONFIG_BACKUP=false
        else
          CONFIG_BACKUP=true
        fi
        echo "[INFO] CONFIG_OVERWRITE=true CONFIG_BACKUP=${CONFIG_BACKUP}"
      fi

      read -t 30 -p "Delete old oMPX sink definitions first? [y/N] (default N): " cfg_prune || cfg_prune="N"
      cfg_prune=${cfg_prune^^}
      if [ "${cfg_prune}" = "Y" ]; then
        REMOVE_OLD_SINKS=true
      else
        REMOVE_OLD_SINKS=false
      fi
    fi
  fi

  echo ""
  echo "Stream configuration options:"
  echo "  H) Read config header (use RADIO1_URL/RADIO2_URL already in script/env)"
  echo "  D) Define now (enter stream URLs during install)"
  echo "  L) Define later (skip stream setup during install)"
  read -t 45 -p "Choose stream setup mode [H/D/L] (default H): " cfg_stream_mode || cfg_stream_mode="H"
  cfg_stream_mode=${cfg_stream_mode^^}

  case "${cfg_stream_mode}" in
    D)
      STREAM_SETUP_MODE="define-now"
      echo "[INFO] Current RADIO1_URL: ${RADIO1_URL}"
      echo "[INFO] Current RADIO2_URL: ${RADIO2_URL}"
      echo "[INFO] RADIO2_URL is optional; a single live stream is supported."
      read -t 120 -p "Enter RADIO1_URL (required only if you want Program 1 enabled; leave empty to keep current): " cfg_radio1 || cfg_radio1=""
      read -t 120 -p "Enter RADIO2_URL (optional; leave empty to keep current or disable Program 2 later): " cfg_radio2 || cfg_radio2=""
      if [ -n "${cfg_radio1}" ]; then RADIO1_URL="${cfg_radio1}"; fi
      if [ -n "${cfg_radio2}" ]; then RADIO2_URL="${cfg_radio2}"; fi
      AUTO_UPDATE_STREAM_URLS_FROM_HEADER=true
      read -t 30 -p "Start configured streams immediately when valid? [y/N] (default N): " cfg_autostart || cfg_autostart="N"
      cfg_autostart=${cfg_autostart^^}
      if [ "${cfg_autostart}" = "Y" ]; then
        AUTO_START_STREAMS_FROM_HEADER=true
      else
        AUTO_START_STREAMS_FROM_HEADER=false
      fi
      ;;
    L)
      STREAM_SETUP_MODE="later"
      AUTO_UPDATE_STREAM_URLS_FROM_HEADER=false
      AUTO_START_STREAMS_FROM_HEADER=false
      echo "[INFO] Stream URLs will be defined after installation via ${OMPX_ADD}."
      ;;
    *)
      STREAM_SETUP_MODE="header"
      read -t 30 -p "Sync header stream URLs during install? [Y/n] (default Y): " cfg_sync_header || cfg_sync_header="Y"
      cfg_sync_header=${cfg_sync_header^^}
      if [ "${cfg_sync_header}" = "N" ]; then
        AUTO_UPDATE_STREAM_URLS_FROM_HEADER=false
        AUTO_START_STREAMS_FROM_HEADER=false
      else
        AUTO_UPDATE_STREAM_URLS_FROM_HEADER=true
        read -t 30 -p "Start header streams immediately when valid? [y/N] (default N): " cfg_start_header || cfg_start_header="N"
        cfg_start_header=${cfg_start_header^^}
        if [ "${cfg_start_header}" = "Y" ]; then
          AUTO_START_STREAMS_FROM_HEADER=true
        else
          AUTO_START_STREAMS_FROM_HEADER=false
        fi
      fi
      ;;
  esac

  echo ""
  ch_count_default="1"
  if [ "${PROGRAM2_ENABLED}" = "true" ] || ! is_placeholder_stream_url "${RADIO2_URL}"; then
    ch_count_default="2"
  fi
  read -t 45 -p "How many channels do you want active now? [1/2] (default ${ch_count_default}): " cfg_channel_count || cfg_channel_count="${ch_count_default}"
  cfg_channel_count="${cfg_channel_count:-${ch_count_default}}"
  case "${cfg_channel_count}" in
    2)
      PROGRAM2_ENABLED="true"
      CHANNEL_MODE_SET_BY_PROMPT="true"
      echo "[INFO] Channel mode: 2-channel (Program 2 enabled)"
      ;;
    *)
      PROGRAM2_ENABLED="false"
      CHANNEL_MODE_SET_BY_PROMPT="true"
      echo "[INFO] Channel mode: 1-channel (Program 2 disabled; Program 1 will be duplicated to L/R)"
      ;;
  esac

  p1_delay_default="${P1_INGEST_DELAY_SEC:-${INGEST_DELAY_SEC}}"
  p2_delay_default="${P2_INGEST_DELAY_SEC:-${INGEST_DELAY_SEC}}"
  read -t 30 -p "Enable built-in broadcast delay? [Y/n] (default Y): " cfg_delay_enable || cfg_delay_enable="Y"
  cfg_delay_enable=${cfg_delay_enable^^}
  if [ "${cfg_delay_enable}" = "N" ]; then
    INGEST_DELAY_SEC="0"
    P1_INGEST_DELAY_SEC="0"
    P2_INGEST_DELAY_SEC="0"
    echo "[INFO] Broadcast delay disabled for all channels"
  else
    read -t 45 -p "Program 1 delay in seconds (default ${p1_delay_default}): " cfg_p1_delay || cfg_p1_delay=""
    if [ -n "${cfg_p1_delay}" ] && [[ "${cfg_p1_delay}" =~ ^[0-9]+$ ]]; then
      P1_INGEST_DELAY_SEC="${cfg_p1_delay}"
    else
      P1_INGEST_DELAY_SEC="${p1_delay_default}"
    fi

    if [ "${PROGRAM2_ENABLED}" = "true" ]; then
      read -t 45 -p "Program 2 delay in seconds (default ${p2_delay_default}): " cfg_p2_delay || cfg_p2_delay=""
      if [ -n "${cfg_p2_delay}" ] && [[ "${cfg_p2_delay}" =~ ^[0-9]+$ ]]; then
        P2_INGEST_DELAY_SEC="${cfg_p2_delay}"
      else
        P2_INGEST_DELAY_SEC="${p2_delay_default}"
      fi
    else
      P2_INGEST_DELAY_SEC="0"
    fi
    echo "[INFO] Broadcast delay configured: P1=${P1_INGEST_DELAY_SEC}s, P2=${P2_INGEST_DELAY_SEC}s"
  fi

  echo ""
  echo "Streaming ingest engine is fixed to FFmpeg."
  echo "  Reason: simpler runtime, fewer moving parts, no Liquidsoap dependency."
  echo "[INFO] Ingest can be any decodable format; non-MPX sink sample rate defaults to ${NON_MPX_SAMPLE_RATE} Hz; Icecast output is fixed to FLAC-in-Ogg at ${ICECAST_SAMPLE_RATE} Hz, ${ICECAST_BIT_DEPTH}-bit."
  STREAM_ENGINE="ffmpeg"
  echo "[INFO] Selected streaming engine: ${STREAM_ENGINE}"
  read -t 30 -p "Enable DSCA sinks/cards? [y/N] (default N): " cfg_dsca || cfg_dsca="N"
  cfg_dsca=${cfg_dsca^^}
  if [ "${cfg_dsca}" = "Y" ]; then
    ENABLE_DSCA_SINKS="true"
  else
    ENABLE_DSCA_SINKS="false"
  fi
  read -t 30 -p "Enable preview sinks/cards? [y/N] (default N): " cfg_preview || cfg_preview="N"
  cfg_preview=${cfg_preview^^}
  if [ "${cfg_preview}" = "Y" ]; then
    ENABLE_PREVIEW_SINKS="true"
  else
    ENABLE_PREVIEW_SINKS="false"
  fi
  read -t 30 -p "Non-MPX sink sample rate in Hz (default ${NON_MPX_SAMPLE_RATE}): " cfg_non_mpx_sr || cfg_non_mpx_sr=""
  if [ -n "${cfg_non_mpx_sr}" ]; then
    if [[ "${cfg_non_mpx_sr}" =~ ^[0-9]+$ ]] && [ "${cfg_non_mpx_sr}" -ge 8000 ] && [ "${cfg_non_mpx_sr}" -le 192000 ]; then
      NON_MPX_SAMPLE_RATE="${cfg_non_mpx_sr}"
    else
      echo "[WARNING] Invalid non-MPX sample rate '${cfg_non_mpx_sr}', keeping ${NON_MPX_SAMPLE_RATE}"
    fi
  fi
  echo "[INFO] ENABLE_DSCA_SINKS=${ENABLE_DSCA_SINKS}"
  echo "[INFO] ENABLE_PREVIEW_SINKS=${ENABLE_PREVIEW_SINKS}"
  echo "[INFO] NON_MPX_SAMPLE_RATE=${NON_MPX_SAMPLE_RATE}"

  echo ""
  echo "Optional multiband module profile (for modules/multiband_agc.sh):"
  echo "  1) waxdreams2-5band (default)"
  echo "  2) waxdreams2-safe"
  echo "  3) fm-loud"
  echo "  4) voice-safe"
  echo "  5) classic-3band"
  echo "  6) decoder-clean"
  echo "  7) talk-heavy"
  echo "  8) music-heavy"
  read -t 45 -p "Select default multiband profile [1-8] (default 1): " cfg_mb_profile || cfg_mb_profile="1"
  case "${cfg_mb_profile}" in
    2) MULTIBAND_PROFILE="waxdreams2-safe" ;;
    3) MULTIBAND_PROFILE="fm-loud" ;;
    4) MULTIBAND_PROFILE="voice-safe" ;;
    5) MULTIBAND_PROFILE="classic-3band" ;;
    6) MULTIBAND_PROFILE="decoder-clean" ;;
    7) MULTIBAND_PROFILE="talk-heavy" ;;
    8) MULTIBAND_PROFILE="music-heavy" ;;
    *) MULTIBAND_PROFILE="waxdreams2-5band" ;;
  esac
  echo "[INFO] Default multiband module profile: ${MULTIBAND_PROFILE}"

  prompt_ompx_web_ui_binding
  if [ "${OMPX_WEB_UI_ENABLE}" = "true" ]; then
    prompt_ompx_web_kiosk
  fi

  echo ""
  echo "Stereo processing backend for FIFO chain wrappers:"
  echo "  1) ompx-mpx    (default)  - wrapper does stereo coding and optional RDS subcarrier injection"
  echo "  2) stereotool             - prefer native Stereo Tool binary if present"
  echo "  3) passthrough            - raw left/right pass-through"
  read -t 45 -p "Select wrapper backend [1-3] (default 1): " cfg_st_backend || cfg_st_backend="1"
  case "${cfg_st_backend}" in
    2) OMPX_STEREO_BACKEND="stereotool" ;;
    3) OMPX_STEREO_BACKEND="passthrough" ;;
    *) OMPX_STEREO_BACKEND="ompx-mpx" ;;
  esac
  read -t 30 -p "Enable RDS subcarrier coding hook in ompx-mpx wrapper? [y/N] (default N): " cfg_rds_wrap || cfg_rds_wrap="N"
  cfg_rds_wrap=${cfg_rds_wrap^^}
  if [ "${cfg_rds_wrap}" = "Y" ]; then
    OMPX_WRAPPER_RDS_ENABLE="true"
    read -t 120 -p "Optional external RDS encoder command (leave empty to use silence): " cfg_rds_cmd || cfg_rds_cmd=""
    OMPX_WRAPPER_RDS_ENCODER_CMD="${cfg_rds_cmd}"
  else
    OMPX_WRAPPER_RDS_ENABLE="false"
    OMPX_WRAPPER_RDS_ENCODER_CMD=""
  fi
  echo "  Wrapper preset options:"
  echo "    C) conservative  B) balanced (default)  H) hot  S) speech"
  read -t 45 -p "Wrapper preset [C/B/H/S] (default B): " cfg_wrap_preset || cfg_wrap_preset="B"
  cfg_wrap_preset=${cfg_wrap_preset^^}
  case "${cfg_wrap_preset}" in
    C) OMPX_WRAPPER_PRESET="conservative" ;;
    H) OMPX_WRAPPER_PRESET="hot" ;;
    S) OMPX_WRAPPER_PRESET="speech" ;;
    *) OMPX_WRAPPER_PRESET="balanced" ;;
  esac
  echo "  FM preemphasis standard:"
  echo "    U) 75 us (US default)"
  echo "    W) 50 us (most of world)"
  echo "    O) Off"
  read -t 45 -p "Select preemphasis [U/W/O] (default U): " cfg_preemph || cfg_preemph="U"
  cfg_preemph=${cfg_preemph^^}
  case "${cfg_preemph}" in
    W) OMPX_FM_PREEMPHASIS="50" ;;
    O) OMPX_FM_PREEMPHASIS="off" ;;
    *) OMPX_FM_PREEMPHASIS="75" ;;
  esac
  read -t 45 -p "Wrapper MPX sample rate Hz (default ${OMPX_WRAPPER_SAMPLE_RATE}): " cfg_wrap_sr || cfg_wrap_sr=""
  if [ -n "${cfg_wrap_sr}" ] && [[ "${cfg_wrap_sr}" =~ ^[0-9]+$ ]] && [ "${cfg_wrap_sr}" -ge 32000 ] && [ "${cfg_wrap_sr}" -le 384000 ]; then
    OMPX_WRAPPER_SAMPLE_RATE="${cfg_wrap_sr}"
  fi
  read -t 45 -p "Wrapper pilot level (0.00-0.20, default ${OMPX_WRAPPER_PILOT_LEVEL}): " cfg_pilot_lvl || cfg_pilot_lvl=""
  if [ -n "${cfg_pilot_lvl}" ] && awk -v v="${cfg_pilot_lvl}" 'BEGIN{exit !(v>=0 && v<=0.2)}'; then
    OMPX_WRAPPER_PILOT_LEVEL="${cfg_pilot_lvl}"
  fi
  read -t 45 -p "Wrapper RDS level (0.00-0.10, default ${OMPX_WRAPPER_RDS_LEVEL}): " cfg_rds_lvl || cfg_rds_lvl=""
  if [ -n "${cfg_rds_lvl}" ] && awk -v v="${cfg_rds_lvl}" 'BEGIN{exit !(v>=0 && v<=0.1)}'; then
    OMPX_WRAPPER_RDS_LEVEL="${cfg_rds_lvl}"
  fi
  echo "[INFO] Wrapper backend: ${OMPX_STEREO_BACKEND} (RDS hook: ${OMPX_WRAPPER_RDS_ENABLE})"
  echo "[INFO] Wrapper preset=${OMPX_WRAPPER_PRESET} preemphasis=${OMPX_FM_PREEMPHASIS}us"
  echo "[INFO] Wrapper levels: sample_rate=${OMPX_WRAPPER_SAMPLE_RATE}, pilot=${OMPX_WRAPPER_PILOT_LEVEL}, rds=${OMPX_WRAPPER_RDS_LEVEL}"

  read -t 30 -p "Set a login password for user ${OMPX_USER}? [y/N] (default N): " cfg_set_pwd || cfg_set_pwd="N"
  cfg_set_pwd=${cfg_set_pwd^^}
  if [ "${cfg_set_pwd}" = "Y" ]; then
    while true; do
      read -r -s -p "Enter password for ${OMPX_USER}: " cfg_pwd_1 || cfg_pwd_1=""
      echo ""
      read -r -s -p "Confirm password for ${OMPX_USER}: " cfg_pwd_2 || cfg_pwd_2=""
      echo ""
      if [ -z "${cfg_pwd_1}" ]; then
        echo "[WARNING] Empty password entered; leaving ${OMPX_USER} password unchanged"
        break
      fi
      if [ "${cfg_pwd_1}" != "${cfg_pwd_2}" ]; then
        echo "[WARNING] Passwords did not match. Try again."
        continue
      fi
      OMPX_USER_PASSWORD="${cfg_pwd_1}"
      break
    done
  else
    echo "[WARNING] No password will be set for user ${OMPX_USER}. Continuing installation."
  fi

  configure_icecast_dialog
  configure_rds_dialog

  echo ""
  FETCH_STEREO_TOOL_ENTERPRISE=false
  ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE=false
  if [ "${OMPX_STEREO_BACKEND}" = "stereotool" ]; then
    if [ -x "${STEREO_TOOL_ENTERPRISE_BIN}" ]; then
      echo "[INFO] Existing Stereo Tool Enterprise binary detected at ${STEREO_TOOL_ENTERPRISE_BIN}."
      read -t 45 -p "Enable Stereo Tool Enterprise service at boot with existing binary? [Y/n] (default Y): " cfg_st_enable_existing || cfg_st_enable_existing="Y"
      cfg_st_enable_existing=${cfg_st_enable_existing^^}
      if [ "${cfg_st_enable_existing}" != "N" ]; then
        ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE=true
        prompt_stereo_tool_limit_preset
        prompt_stereo_tool_web_binding
        read -t 45 -p "Start Stereo Tool Enterprise immediately after install (no reboot)? [Y/n] (default Y): " cfg_st_start_now || cfg_st_start_now="Y"
        cfg_st_start_now=${cfg_st_start_now^^}
        if [ "${cfg_st_start_now}" = "N" ]; then
          START_STEREO_TOOL_AFTER_INSTALL=false
        else
          START_STEREO_TOOL_AFTER_INSTALL=true
        fi
      fi
    else
      read -t 45 -p "Stereo Tool Enterprise not found locally. Download latest for Linux during install? [y/N] (default N): " cfg_st_fetch || cfg_st_fetch="N"
      cfg_st_fetch=${cfg_st_fetch^^}
      if [ "${cfg_st_fetch}" = "Y" ]; then
        FETCH_STEREO_TOOL_ENTERPRISE=true
        if [ -n "${STEREO_TOOL_ENTERPRISE_URL}" ]; then
          echo "[INFO] Current Stereo Tool Enterprise URL from environment: ${STEREO_TOOL_ENTERPRISE_URL}"
        fi
        read -t 180 -p "Enter Stereo Tool Enterprise Linux URL (leave empty to keep current): " cfg_st_url || cfg_st_url=""
        if [ -n "${cfg_st_url}" ]; then
          STEREO_TOOL_ENTERPRISE_URL="${cfg_st_url}"
        fi
        ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE=true
        prompt_stereo_tool_limit_preset
        prompt_stereo_tool_web_binding
        read -t 45 -p "Start Stereo Tool Enterprise immediately after install (no reboot)? [Y/n] (default Y): " cfg_st_start_now || cfg_st_start_now="Y"
        cfg_st_start_now=${cfg_st_start_now^^}
        if [ "${cfg_st_start_now}" = "N" ]; then
          START_STEREO_TOOL_AFTER_INSTALL=false
        else
          START_STEREO_TOOL_AFTER_INSTALL=true
        fi
      fi
    fi
  else
    AUTO_ENABLE_STEREO_TOOL_IF_PRESENT="false"
    START_STEREO_TOOL_AFTER_INSTALL="false"
    echo "[INFO] OMPX_STEREO_BACKEND=${OMPX_STEREO_BACKEND}; Stereo Tool Enterprise boot service will be removed/disabled."
  fi

  echo "[INFO] Quick loopback self-test is disabled by default (historically unreliable on some hosts)."
fi

cat > "${ASOUND_MAP_HELPER}" <<'ASMAP'
#!/usr/bin/env bash
set -euo pipefail
PROFILE="/home/ompx/.profile"
ENABLE_DSCA_SINKS="${ENABLE_DSCA_SINKS:-false}"
ENABLE_PREVIEW_SINKS="${ENABLE_PREVIEW_SINKS:-false}"
PROGRAM2_ENABLED="${PROGRAM2_ENABLED:-false}"
if [ -f "${PROFILE}" ]; then
  # shellcheck disable=SC1090
  . "${PROFILE}" || true
fi
ENABLE_DSCA_SINKS="${ENABLE_DSCA_SINKS,,}"
ENABLE_PREVIEW_SINKS="${ENABLE_PREVIEW_SINKS,,}"
PROGRAM2_ENABLED="${PROGRAM2_ENABLED,,}"

echo "oMPX sink map helper"
echo "--------------------"
echo "Write/playback endpoints (send audio into these):"
for id in ompx_prg1in ompx_prg1mpx ompx_mpx_to_icecast; do
  printf '  %s\n' "$id"
done
if [ "${PROGRAM2_ENABLED}" = "true" ]; then
  for id in ompx_prg2in ompx_prg2mpx; do
    printf '  %s\n' "$id"
  done
fi
if [ "${ENABLE_PREVIEW_SINKS}" = "true" ]; then
  for id in ompx_prg1prev; do
    printf '  %s\n' "$id"
  done
  if [ "${PROGRAM2_ENABLED}" = "true" ]; then
    printf '  %s\n' "ompx_prg2prev"
  fi
fi
if [ "${ENABLE_DSCA_SINKS}" = "true" ]; then
  for id in ompx_dsca_src ompx_dsca_injection; do
    printf '  %s\n' "$id"
  done
fi
echo "Friendly playback aliases:"
for id in ompx_program1_input ompx_program1_mpx_output ompx_mpx_to_icecast; do
  printf '  %s\n' "$id"
done
if [ "${PROGRAM2_ENABLED}" = "true" ]; then
  for id in ompx_program2_input ompx_program2_mpx_output; do
    printf '  %s\n' "$id"
  done
fi
if [ "${ENABLE_PREVIEW_SINKS}" = "true" ]; then
  for id in ompx_program1_preview; do
    printf '  %s\n' "$id"
  done
  if [ "${PROGRAM2_ENABLED}" = "true" ]; then
    printf '  %s\n' "ompx_program2_preview"
  fi
fi
if [ "${ENABLE_DSCA_SINKS}" = "true" ]; then
  for id in ompx_dsca_source ompx_dsca_injection; do
    printf '  %s\n' "$id"
  done
fi
echo ""
echo "Read/capture endpoints (read audio back from these):"
for id in ompx_prg1in_cap ompx_prg1mpx_cap; do
  printf '  %s\n' "$id"
done
if [ "${PROGRAM2_ENABLED}" = "true" ]; then
  for id in ompx_prg2in_cap ompx_prg2mpx_cap; do
    printf '  %s\n' "$id"
  done
fi
if [ "${ENABLE_PREVIEW_SINKS}" = "true" ]; then
  for id in ompx_prg1prev_cap; do
    printf '  %s\n' "$id"
  done
  if [ "${PROGRAM2_ENABLED}" = "true" ]; then
    printf '  %s\n' "ompx_prg2prev_cap"
  fi
fi
if [ "${ENABLE_DSCA_SINKS}" = "true" ]; then
  printf '  %s\n' "ompx_dsca_src_cap"
fi
echo "Friendly capture aliases:"
for id in ompx_program1_input_capture ompx_program1_mpx_output_capture; do
  printf '  %s\n' "$id"
done
if [ "${PROGRAM2_ENABLED}" = "true" ]; then
  for id in ompx_program2_input_capture ompx_program2_mpx_output_capture; do
    printf '  %s\n' "$id"
  done
fi
if [ "${ENABLE_PREVIEW_SINKS}" = "true" ]; then
  for id in ompx_program1_preview_capture; do
    printf '  %s\n' "$id"
  done
  if [ "${PROGRAM2_ENABLED}" = "true" ]; then
    printf '  %s\n' "ompx_program2_preview_capture"
  fi
fi
if [ "${ENABLE_DSCA_SINKS}" = "true" ]; then
  printf '  %s\n' "ompx_dsca_source_capture"
fi
ASMAP
chmod 755 "${ASOUND_MAP_HELPER}"
chown root:root "${ASOUND_MAP_HELPER}"

cat > "${ASOUND_SWITCH_HELPER}" <<'ASWITCH'
#!/usr/bin/env bash
set -euo pipefail
if [ -f /etc/asound.conf.ompx-staged ]; then
  cp -f /etc/asound.conf.ompx-staged /etc/asound.conf
  chmod 644 /etc/asound.conf
  echo "Promoted /etc/asound.conf.ompx-staged -> /etc/asound.conf"
else
  echo "No staged ALSA profile found at /etc/asound.conf.ompx-staged"
fi
ASWITCH
chmod 755 "${ASOUND_SWITCH_HELPER}"
chown root:root "${ASOUND_SWITCH_HELPER}"

WANT_ASOUND_TEST="$(render_asound_config "${LOOPBACK_CARD_REF}")"

if [ "${CONFIG_SKIP}" = false ]; then
  if [ "${CONFIG_OVERWRITE}" = true ]; then
    if [ -f "${ASOUND_CONF_PATH}" ]; then
      tmp_clean=$(mktemp)
      strip_old_ompx_sinks "${ASOUND_CONF_PATH}" "${tmp_clean}" || true
      tmp_clean2=$(mktemp)
      strip_legacy_hw_references "${tmp_clean}" "${tmp_clean2}" || true
      cp -f "${tmp_clean2}" "${ASOUND_CONF_PATH}" || true
      rm -f "${tmp_clean}" "${tmp_clean2}" || true
      echo "[INFO] Removed old oMPX sink blocks and legacy hw:* references from ${ASOUND_CONF_PATH}"
    fi
    if [ -f "${ASOUND_CONF_PATH}" ] && [ "${CONFIG_BACKUP}" = true ]; then
      cp -a "${ASOUND_CONF_PATH}" "${ASOUND_CONF_PATH}.bak.$(date +%s)" || true
      echo "[INFO] Backed up existing ${ASOUND_CONF_PATH}"
    fi
    printf '%s\n' "${WANT_ASOUND_TEST}" > "${ASOUND_CONF_PATH}"
    chmod 644 "${ASOUND_CONF_PATH}" || true
    _log "Wrote ${ASOUND_CONF_PATH}"
    echo "[SUCCESS] ALSA config written: ${ASOUND_CONF_PATH}"
  else
    if [ -f "${ASOUND_CONF_PATH}" ]; then
      tmp_stage=$(mktemp)
      cp -f "${ASOUND_CONF_PATH}" "${tmp_stage}" || true
      tmp_clean_stage=$(mktemp)
      strip_old_ompx_sinks "${tmp_stage}" "${tmp_clean_stage}" || true
      mv -f "${tmp_clean_stage}" "${tmp_stage}"
      tmp_clean_stage2=$(mktemp)
      strip_legacy_hw_references "${tmp_stage}" "${tmp_clean_stage2}" || true
      mv -f "${tmp_clean_stage2}" "${tmp_stage}"
      echo "[INFO] Removed old oMPX sink blocks and legacy hw:* references from staged source"
      printf '\n%s\n' "${WANT_ASOUND_TEST}" >> "${tmp_stage}"
      cp -f "${tmp_stage}" /etc/asound.conf.ompx-staged
      rm -f "${tmp_stage}" || true
    else
      printf '%s\n' "${WANT_ASOUND_TEST}" > /etc/asound.conf.ompx-staged
    fi
    chmod 644 /etc/asound.conf.ompx-staged || true
    echo "[INFO] Staged ALSA config: /etc/asound.conf.ompx-staged"
    echo "[INFO] Promote later with: sudo ${ASOUND_SWITCH_HELPER}"
  fi
else
  echo "[INFO] Skipping asound.conf changes (CONFIG_SKIP=true)"
fi
# --- Check existing installation ---
echo "[INFO] Checking for existing oMPX installation..."

found=0
msg=""
if id -u "${OMPX_USER}" >/dev/null 2>&1; then found=1; msg="${msg}user:${OMPX_USER} "; fi
if [ -d "${SYS_SCRIPTS_DIR}" ]; then found=1; msg="${msg}${SYS_SCRIPTS_DIR} "; fi
if has_systemd && systemctl list-unit-files | grep -q '^mpx-processing-alsa.service'; then found=1; msg="${msg}mpx-processing-alsa.service "; fi
[ "$found" -eq 0 ] && echo "[INFO] No existing installation detected (fresh install)" || echo "[WARNING] Existing installation found: $msg"

if [ "$found" -eq 1 ]; then
echo ""
echo "Existing oMPX installation detected (${msg})."
echo "Choose action:"
echo "  K) Keep existing (overwrite generated files only)"
echo "  R) Reinstall (clean -> fresh install)  *recommended for broken installs*"
echo "  U) Uninstall (remove all oMPX components)"
echo "  A) Abort (do nothing)"
echo ""
prompt_helper choice "Select [K/R/U/A] (default K): " K 30
choice=${choice^^}
echo "[INFO] User selected: $choice"
case "$choice" in
R)
echo "[INFO] Performing full cleanup before reinstall..."
echo "[INFO] Stopping systemd services..."
systemctl stop mpx-processing-alsa.service mpx-watchdog.service mpx-stream-pull.service mpx-source1.service mpx-source2.service rds-sync-prog1.service rds-sync-prog2.service 2>/dev/null || true
systemctl stop stereo-tool-enterprise.service ompx-web-ui.service ompx-web-kiosk.service 2>/dev/null || true
echo "[INFO] Disabling systemd services..."
systemctl disable mpx-processing-alsa.service mpx-watchdog.service mpx-stream-pull.service mpx-source1.service mpx-source2.service rds-sync-prog1.service rds-sync-prog2.service 2>/dev/null || true
systemctl disable stereo-tool-enterprise.service ompx-web-ui.service ompx-web-kiosk.service 2>/dev/null || true
rm -f "${SYSTEMD_DIR}/mpx-processing-alsa.service" "${SYSTEMD_DIR}/mpx-watchdog.service" "${OMPX_STREAM_PULL_SERVICE}" "${OMPX_SOURCE1_SERVICE}" "${OMPX_SOURCE2_SERVICE}" "${RDS_SYNC_PROG1_SERVICE}" "${RDS_SYNC_PROG2_SERVICE}" "${STEREO_TOOL_ENTERPRISE_SERVICE}" "${OMPX_WEB_UI_SERVICE}" "${OMPX_WEB_KIOSK_SERVICE}" "${STEREO_TOOL_ENTERPRISE_LAUNCHER}" "${SYS_SCRIPTS_DIR}/ompx-web-ui.py" "${SYS_SCRIPTS_DIR}/ompx-web-kiosk.sh"
systemctl daemon-reload || true
echo "[INFO] Removing old cron jobs..."
if have_crontab && id -u "${OMPX_USER}" >/dev/null 2>&1; then
crontab -u "${OMPX_USER}" -l 2>/dev/null | grep -v "${SYS_SCRIPTS_DIR}/source" | sed '/^$/d' | crontab -u "${OMPX_USER}" - 2>/dev/null || true
else
echo "[WARNING] crontab command not found; skipping cron cleanup"
fi
echo "[INFO] Removing old files and directories..."
rm -f "${STEREO_TOOL_WRAPPER}" "${STEREO_TOOL_WRAPPER}.real-check" "${OMPX_ADD}"
rm -rf "${SYS_SCRIPTS_DIR}" "${OMPX_LOG_DIR}" /var/log/radio-opus1.log /var/log/radio-opus2.log /var/log/radio-source1.log /var/log/radio-source2.log
rm -f "${OMPX_AUDIO_UDEV_RULE}" || true
rm -f "${OMPX_HOME}/.profile" "${OMPX_HOME}/.profile".bak.* || true
echo "[INFO] Removing oMPX user..."
if id -u "${OMPX_USER}" >/dev/null 2>&1; then userdel -r "${OMPX_USER}" || true; fi
echo "[INFO] Unloading snd_aloop module..."
modprobe -r snd_aloop 2>/dev/null || true
echo "[SUCCESS] Cleanup complete, ready for fresh install"
;;
U)
echo "[INFO] Performing full uninstall..."
echo "[INFO] Stopping systemd services..."
systemctl stop mpx-processing-alsa.service mpx-watchdog.service mpx-stream-pull.service mpx-source1.service mpx-source2.service rds-sync-prog1.service rds-sync-prog2.service 2>/dev/null || true
systemctl stop stereo-tool-enterprise.service ompx-web-ui.service ompx-web-kiosk.service 2>/dev/null || true
echo "[INFO] Disabling systemd services..."
systemctl disable mpx-processing-alsa.service mpx-watchdog.service mpx-stream-pull.service mpx-source1.service mpx-source2.service rds-sync-prog1.service rds-sync-prog2.service 2>/dev/null || true
systemctl disable stereo-tool-enterprise.service ompx-web-ui.service ompx-web-kiosk.service 2>/dev/null || true
rm -f "${SYSTEMD_DIR}/mpx-processing-alsa.service" "${SYSTEMD_DIR}/mpx-watchdog.service" "${OMPX_STREAM_PULL_SERVICE}" "${OMPX_SOURCE1_SERVICE}" "${OMPX_SOURCE2_SERVICE}" "${RDS_SYNC_PROG1_SERVICE}" "${RDS_SYNC_PROG2_SERVICE}" "${STEREO_TOOL_ENTERPRISE_SERVICE}" "${OMPX_WEB_UI_SERVICE}" "${OMPX_WEB_KIOSK_SERVICE}" "${STEREO_TOOL_ENTERPRISE_LAUNCHER}" "${SYS_SCRIPTS_DIR}/ompx-web-ui.py" "${SYS_SCRIPTS_DIR}/ompx-web-kiosk.sh"
systemctl daemon-reload || true
echo "[INFO] Removing cron jobs..."
if have_crontab && id -u "${OMPX_USER}" >/dev/null 2>&1; then
crontab -u "${OMPX_USER}" -l 2>/dev/null | grep -v "${SYS_SCRIPTS_DIR}/source" | sed '/^$/d' | crontab -u "${OMPX_USER}" - 2>/dev/null || true
else
echo "[WARNING] crontab command not found; skipping cron cleanup"
fi
echo "[INFO] Removing files and directories..."
rm -f "${STEREO_TOOL_WRAPPER}" "${STEREO_TOOL_WRAPPER}.real-check" "${OMPX_ADD}"
rm -rf "${SYS_SCRIPTS_DIR}" "${OMPX_LOG_DIR}" /var/log/radio-opus1.log /var/log/radio-opus2.log /var/log/radio-source1.log /var/log/radio-source2.log
rm -f "${OMPX_AUDIO_UDEV_RULE}" || true
rm -f "${OMPX_HOME}/.profile" "${OMPX_HOME}/.profile".bak.* || true
echo "[INFO] Removing oMPX user..."
if id -u "${OMPX_USER}" >/dev/null 2>&1; then userdel -r "${OMPX_USER}" || true; fi
echo "[INFO] Unloading snd_aloop module..."
modprobe -r snd_aloop 2>/dev/null || true
echo "[SUCCESS] Uninstall complete."
exit 0
;;
K)
echo "[INFO] Keeping existing installation; generated files will be overwritten."
;;
*)
echo "[INFO] Aborting installation (user selected option)."
exit 0;;
esac
fi
echo "[INFO] Setting up oMPX system user..."

if ! id -u "${OMPX_USER}" >/dev/null 2>&1; then
echo "[INFO] Creating user ${OMPX_USER}..."
useradd --home-dir "${OMPX_HOME}" --create-home --shell "${OMPX_SHELL}" --comment "oMPX service account" "${OMPX_USER}"
if getent group audio >/dev/null 2>&1; then
  usermod -aG audio "${OMPX_USER}" || true
fi
echo "[SUCCESS] User ${OMPX_USER} created"
else
echo "[INFO] User ${OMPX_USER} already exists; ensuring shell is ${OMPX_SHELL}."
_log "User ${OMPX_USER} exists; ensuring shell is ${OMPX_SHELL}."
usermod -s "${OMPX_SHELL}" "${OMPX_USER}" || true
usermod -d "${OMPX_HOME}" -m "${OMPX_USER}" || true
if getent group audio >/dev/null 2>&1; then
  usermod -aG audio "${OMPX_USER}" || true
fi
echo "[SUCCESS] User shell updated"
fi

ensure_ompx_alsa_access
apply_ompx_user_password "${OMPX_USER_PASSWORD}"
echo "[INFO] ${OMPX_USER} groups after ALSA access fix: $(id -nG "${OMPX_USER}" 2>/dev/null || echo unknown)"

# --- Write profile (overwrite) ---
write_profile_file
# --- Create directories, install packages ---
echo "[INFO] Creating system directories..."

mkdir -p "${SYS_SCRIPTS_DIR}" "${FIFOS_DIR}" "${OMPX_LOG_DIR}"
chown -R "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}"
chown -R "${OMPX_USER}:${OMPX_USER}" "${OMPX_LOG_DIR}"
chmod 755 "${SYS_SCRIPTS_DIR}" "${FIFOS_DIR}"
chmod 755 "${OMPX_LOG_DIR}"
echo "[SUCCESS] Directories created at ${SYS_SCRIPTS_DIR}"

echo "[INFO] Updating package lists..."
safe_apt_update
echo "[INFO] Installing base dependencies (curl, wget, alsa-utils, ffmpeg, sox, ladspa-sdk, swh-plugins, cron, python3)..."
DEBIAN_FRONTEND=noninteractive apt install -y curl wget alsa-utils ffmpeg sox ladspa-sdk swh-plugins cron python3
if [ "${OMPX_WEB_KIOSK_ENABLE}" = "true" ] && { [ "${OMPX_WEB_KIOSK_INSTALL_MISSING}" = "true" ] || ! has_chromium_binary || ! has_x11_runtime_tools; }; then
  echo "[INFO] Installing kiosk dependencies (chromium + x11 runtime tools)..."
  if ! DEBIAN_FRONTEND=noninteractive apt install -y chromium x11-xserver-utils x11-utils xinit; then
    echo "[WARNING] Failed to install one or more kiosk dependencies; disabling kiosk mode"
    OMPX_WEB_KIOSK_ENABLE="false"
  fi
fi
if [ "${OMPX_WEB_KIOSK_ENABLE}" = "true" ] && ! has_chromium_binary; then
  echo "[WARNING] Chromium binary not found after install attempt; disabling kiosk mode"
  OMPX_WEB_KIOSK_ENABLE="false"
fi
if [ "${ICECAST_MODE}" = "local" ]; then
  install_icecast_local
fi
if [ -n "${KERNEL_HELPER_PACKAGE}" ]; then
  echo "[INFO] Installing kernel helper package for this OS: ${KERNEL_HELPER_PACKAGE}"
  DEBIAN_FRONTEND=noninteractive apt install -y "${KERNEL_HELPER_PACKAGE}" || echo "[WARNING] Optional package ${KERNEL_HELPER_PACKAGE} could not be installed"
else
  echo "[INFO] No automatic kernel helper package selected for this environment"
fi
echo "[SUCCESS] Dependencies installed"

if [ "${FETCH_STEREO_TOOL_ENTERPRISE}" = true ]; then
  download_stereo_tool_enterprise "${STEREO_TOOL_ENTERPRISE_URL}" "${STEREO_TOOL_DOWNLOAD_DIR}" "${STEREO_TOOL_ENTERPRISE_BIN}"
  ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE=true
fi

# Fail-safe: on systemd hosts, auto-enable service when binary already exists.
if has_systemd && [ "${OMPX_STEREO_BACKEND}" = "stereotool" ] && [ "${AUTO_ENABLE_STEREO_TOOL_IF_PRESENT}" = "true" ] && [ -x "${STEREO_TOOL_ENTERPRISE_BIN}" ]; then
  if [ "${ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE}" != "true" ]; then
    echo "[INFO] Stereo Tool Enterprise binary detected; auto-enabling boot service (AUTO_ENABLE_STEREO_TOOL_IF_PRESENT=true)"
  fi
  ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE=true
fi

if [ "${ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE}" = true ]; then
  apply_stereo_tool_start_limit_preset
  install_stereo_tool_enterprise_service "${STEREO_TOOL_ENTERPRISE_BIN}" "${STEREO_TOOL_ENTERPRISE_LAUNCHER}" "${STEREO_TOOL_WEB_BIND}" "${STEREO_TOOL_WEB_PORT}" "${STEREO_TOOL_WEB_WHITELIST}" "${STEREO_TOOL_START_LIMIT_INTERVAL_SEC}" "${STEREO_TOOL_START_LIMIT_BURST}"
elif [ "${OMPX_STEREO_BACKEND}" != "stereotool" ]; then
  remove_stereo_tool_enterprise_service
fi

if [ "${STREAM_SETUP_MODE:-header}" != "later" ]; then
  if [ "${STREAM_VALIDATION_ENABLED}" = "true" ]; then
    validate_stream_source_interactive 1 RADIO1_URL
    validate_stream_source_interactive 2 RADIO2_URL
  else
    echo "[INFO] Stream URL validation is disabled (STREAM_VALIDATION_ENABLED=false). Continuing with configured URLs."
  fi

  active_streams=0
  if ! is_placeholder_stream_url "${RADIO1_URL}"; then
    active_streams=$((active_streams + 1))
  fi
  if ! is_placeholder_stream_url "${RADIO2_URL}"; then
    active_streams=$((active_streams + 1))
  fi

  if [ "${active_streams}" -ge 1 ]; then
    echo "[INFO] Stream availability summary: ${active_streams} configured stream(s). One live stream is sufficient; Program 2 is optional."
  else
    echo "[INFO] Stream availability summary: no active stream URLs configured yet. Installation will continue; you can add streams later with ${OMPX_ADD}."
  fi

  if [ "${ENV_PROGRAM2_ENABLED_SET}" != "x" ] && [ "${CHANNEL_MODE_SET_BY_PROMPT}" != "true" ]; then
    if is_placeholder_stream_url "${RADIO2_URL}"; then
      PROGRAM2_ENABLED="false"
    else
      PROGRAM2_ENABLED="true"
    fi
  fi
  echo "[INFO] PROGRAM2_ENABLED=${PROGRAM2_ENABLED}"

  write_profile_file
else
  echo "[INFO] Stream setup mode is 'define later'; skipping stream validation"
fi

# --- Ensure snd_aloop loaded and show devices ---
echo "[INFO] Verifying snd_aloop kernel module..."

if ! lsmod | grep -q snd_aloop; then
  echo "[INFO] Attempting to load snd_aloop..."
  if ! load_ompx_aloop_profile; then
    if [ -n "${KERNEL_HELPER_PACKAGE}" ]; then
      echo "[WARNING] Initial snd_aloop load failed. Trying kernel helper package: ${KERNEL_HELPER_PACKAGE}"
      if ! DEBIAN_FRONTEND=noninteractive apt install -y "${KERNEL_HELPER_PACKAGE}"; then
        echo "[WARNING] Package ${KERNEL_HELPER_PACKAGE} could not be installed or is unavailable"
      fi
    elif [ "${IS_PROXMOX}" = true ]; then
      echo "[WARNING] snd_aloop failed to load on Proxmox kernel $(uname -r)."
      echo "[WARNING] Workaround: install and boot a standard Debian kernel (linux-image-amd64), then rerun installer."
      echo "[WARNING] Installer will continue without hard-stopping."
    else
      echo "[WARNING] No kernel helper package configured for this OS (${OS_ID}); continuing."
    fi
    echo "[INFO] Retrying snd_aloop load after helper/workaround step..."
    if load_ompx_aloop_profile; then
      echo "[SUCCESS] snd_aloop loaded after helper/workaround step"
      _log "snd_aloop loaded after helper/workaround step"
    else
      if modinfo snd_aloop >/dev/null 2>&1; then
        echo "[WARNING] snd_aloop module is present but failed to load"
      else
        echo "[WARNING] snd_aloop module is not present in this kernel's module tree"
      fi
      echo "[WARNING] Could not load snd_aloop after kernel package install"
    fi
  fi
else
  echo "[SUCCESS] snd_aloop is loaded"
  _log "snd_aloop loaded"
fi

LOOPBACK_CARD_REF="$(detect_loopback_card_ref)"
WANT_ASOUND_TEST="$(render_asound_config "${LOOPBACK_CARD_REF}")"
echo "[INFO] Using loopback card reference: ${LOOPBACK_CARD_REF}"
if [ "${CONFIG_SKIP}" = false ]; then
  if [ "${CONFIG_OVERWRITE}" = true ]; then
    if [ -f "${ASOUND_CONF_PATH}" ]; then
      tmp_clean=$(mktemp)
      strip_legacy_hw_references "${ASOUND_CONF_PATH}" "${tmp_clean}" || true
      rm -f "${tmp_clean}" || true
    fi
    printf '%s\n' "${WANT_ASOUND_TEST}" > "${ASOUND_CONF_PATH}"
    chmod 644 "${ASOUND_CONF_PATH}" || true
    echo "[INFO] Refreshed ${ASOUND_CONF_PATH} with detected loopback card reference (legacy hw refs removed)"
  else
    printf '%s\n' "${WANT_ASOUND_TEST}" > /etc/asound.conf.ompx-staged
    chmod 644 /etc/asound.conf.ompx-staged || true
    echo "[INFO] Refreshed /etc/asound.conf.ompx-staged with detected loopback card reference"
  fi
fi

sleep 1
echo "[INFO] Available ALSA devices:"
aplay -l 2>/dev/null || echo "[WARNING] No ALSA devices found"
echo "[INFO] Hardware-only list above (aplay -l). Virtual named PCMs are shown with: aplay -L"
_log "ALSA devices listed above"
expected_playback="ompx_prg1in, ompx_prg1mpx, ompx_mpx_to_icecast"
expected_capture="ompx_prg1in_cap, ompx_prg1mpx_cap"
if [ "${PROGRAM2_ENABLED}" = "true" ]; then
  expected_playback="${expected_playback}, ompx_prg2in, ompx_prg2mpx"
  expected_capture="${expected_capture}, ompx_prg2in_cap, ompx_prg2mpx_cap"
fi
if [ "${ENABLE_PREVIEW_SINKS}" = "true" ]; then
  expected_playback="${expected_playback}, ompx_prg1prev"
  expected_capture="${expected_capture}, ompx_prg1prev_cap"
  if [ "${PROGRAM2_ENABLED}" = "true" ]; then
    expected_playback="${expected_playback}, ompx_prg2prev"
    expected_capture="${expected_capture}, ompx_prg2prev_cap"
  fi
fi
if [ "${ENABLE_DSCA_SINKS}" = "true" ]; then
  expected_playback="${expected_playback}, ompx_dsca_src, ompx_dsca_injection"
  expected_capture="${expected_capture}, ompx_dsca_src_cap"
fi
echo "[INFO] Expected named ALSA PCMs: write/playback endpoints ${expected_playback}; read/capture endpoints ${expected_capture}"
echo "[INFO] Resolved sink map helper: ${ASOUND_MAP_HELPER}"
"${ASOUND_MAP_HELPER}" || true

if [ "${CONFIG_SKIP}" = true ]; then
  echo "[INFO] Skipping live ALSA named-PCM validation because asound.conf changes were disabled"
elif [ "${CONFIG_OVERWRITE}" = false ]; then
  echo "[INFO] Skipping live ALSA named-PCM validation because config was staged, not applied"
  echo "[INFO] Promote the staged config first with: sudo ${ASOUND_SWITCH_HELPER}"
else
  while true; do
    playback_ok=0
    capture_ok=0
    if aplay -L 2>/dev/null | grep -Eq '(^|[[:space:]])ompx_prg1in($|[[:space:]])'; then playback_ok=1; fi
    if arecord -L 2>/dev/null | grep -Eq '(^|[[:space:]])ompx_prg1in_cap($|[[:space:]])'; then capture_ok=1; fi

    if [ "${playback_ok}" -eq 1 ] && [ "${capture_ok}" -eq 1 ]; then
      break
    fi

    echo "[WARNING] Named PCM discovery did not return expected endpoints yet."
    if [ "${playback_ok}" -ne 1 ]; then
      echo "[WARNING] Missing from aplay -L: ompx_prg1in (write/playback endpoint)"
    fi
    if [ "${capture_ok}" -ne 1 ]; then
      echo "[WARNING] Missing from arecord -L: ompx_prg1in_cap (read/capture endpoint)"
    fi

    if [ -f "${ASOUND_CONF_PATH}" ]; then
      if grep -Eq '^[[:space:]]*pcm\.ompx_prg1in[[:space:]]*\{' "${ASOUND_CONF_PATH}" && grep -Eq '^[[:space:]]*pcm\.ompx_prg1in_cap[[:space:]]*\{' "${ASOUND_CONF_PATH}"; then
        echo "[INFO] ${ASOUND_CONF_PATH} contains Program 1 input PCM definitions."
      else
        echo "[WARNING] ${ASOUND_CONF_PATH} does not appear to contain both Program 1 input write/capture definitions."
      fi
    fi

    echo "[INFO] Current matching devices from ALSA discovery:"
    echo "[INFO] aplay -L | grep -E 'ompx_prg1in'"
    aplay -L 2>/dev/null | grep -E 'ompx_prg1in' || true
    echo "[INFO] arecord -L | grep -E 'ompx_prg1in_cap'"
    arecord -L 2>/dev/null | grep -E 'ompx_prg1in_cap' || true

    if [ -t 0 ]; then
      echo "[PROMPT] Named PCM check is incomplete."
      echo "  R) Retry discovery"
      echo "  C) Continue anyway"
      echo "  A) Abort installation"
      read -t 60 -p "Select [R/C/A] (default C): " pcm_choice || pcm_choice="C"
      pcm_choice=${pcm_choice^^}
      case "${pcm_choice}" in
        R)
          echo "[INFO] Retrying named PCM discovery..."
          sleep 1
          ;;
        C)
          echo "[WARNING] Continuing with incomplete named PCM discovery"
          break
          ;;
        A)
          echo "[ERROR] Aborting at user request due to named PCM check failure"
          exit 1
          ;;
        *)
          echo "[WARNING] Unrecognized selection; continuing with incomplete named PCM discovery"
          break
          ;;
      esac
    else
      echo "[WARNING] Non-interactive mode and named PCM check failed; continuing anyway"
      break
    fi
  done
fi

if false && [ "${RUN_QUICK_AUDIO_TEST}" = true ] && [ "${CONFIG_SKIP}" = false ] && [ "${CONFIG_OVERWRITE}" = true ]; then
  test_attempt=1
  while true; do
    echo "[INFO] Running quick loopback self-test attempt ${test_attempt}: write to ompx_prg1in, read from ompx_prg1in_cap"
    test_wav=$(mktemp --suffix=.wav)
    test_tone=$(mktemp --suffix=.wav)
    test_capture_log=$(mktemp)
    test_inject_log=$(mktemp)
    test_size=0
    test_rms=0
    ffmpeg_volume_output=""
    ffmpeg_max_volume=""
    sox -n -r ${NON_MPX_SAMPLE_RATE} -c 2 -b 16 "${test_tone}" synth 1.8 sine 1000 vol 0.6 >/dev/null 2>&1 || true

    if arecord -D ompx_prg1in_cap -f S16_LE -c 2 -r ${NON_MPX_SAMPLE_RATE} -d 2 "${test_wav}" >"${test_capture_log}" 2>&1 & then
      rec_pid=$!
      sleep 0.6

      inject_ok=0
      if [ -s "${test_tone}" ]; then
        if timeout 4 aplay -q -D ompx_prg1in "${test_tone}" >"${test_inject_log}" 2>&1; then
          inject_ok=1
        fi
      fi

      if [ "${inject_ok}" -ne 1 ]; then
        if ffmpeg -hide_banner -loglevel error -f lavfi -i "sine=frequency=1000:sample_rate=${NON_MPX_SAMPLE_RATE}:duration=1.8" -ac 2 -f alsa ompx_prg1in >"${test_inject_log}" 2>&1; then
          inject_ok=1
        fi
      fi

      wait "${rec_pid}" >/dev/null 2>&1 || true

      sox_stats=""
      sox_stats=$(sox "${test_wav}" -n stat 2>&1 || true)
      test_peak=$(printf '%s\n' "${sox_stats}" | awk '/Maximum amplitude/ {print $3; exit}')
      test_rms=$(printf '%s\n' "${sox_stats}" | awk '/RMS[[:space:]]+amplitude/ {print $3; exit}')
      test_peak=${test_peak:-0}
      test_rms=${test_rms:-0}
      test_size=$(stat -c %s "${test_wav}" 2>/dev/null || echo 0)

      if ! awk -v p="${test_peak:-0}" -v r="${test_rms:-0}" 'BEGIN { exit !((p + 0) > 0.0005 || (r + 0) > 0.0001) }'; then
        ffmpeg_volume_output=$(ffmpeg -hide_banner -loglevel info -i "${test_wav}" -af volumedetect -f null - 2>&1 || true)
        ffmpeg_max_volume=$(printf '%s\n' "${ffmpeg_volume_output}" | awk -F': ' '/max_volume/ {print $2; exit}')
        ffmpeg_max_volume=${ffmpeg_max_volume%% *}
      fi
      rm -f "${test_wav}" "${test_tone}" || true

      if awk -v p="${test_peak:-0}" -v r="${test_rms:-0}" -v s="${test_size:-0}" -v m="${ffmpeg_max_volume:--inf}" 'BEGIN { exit !(((p + 0) > 0.0005) || ((r + 0) > 0.0001) || ((s + 0) > 4096 && m != "-inf" && m != "")) }'; then
        echo "[SUCCESS] Quick loopback self-test passed (peak amplitude ${test_peak}, RMS amplitude ${test_rms}, capture bytes ${test_size})"
        rm -f "${test_capture_log}" "${test_inject_log}" || true
        break
      fi

      echo "[WARNING] Quick loopback self-test detected silence/low signal (peak amplitude ${test_peak}, RMS amplitude ${test_rms}, capture bytes ${test_size}, ffmpeg max_volume ${ffmpeg_max_volume:--inf})"
      if [ "${inject_ok}" -ne 1 ]; then
        echo "[WARNING] Tone injection into ompx_prg1in (write/playback endpoint) failed. Last injector output:"
        tail -n 3 "${test_inject_log}" 2>/dev/null || true
      fi
      if awk -v p="${test_peak:-0}" -v r="${test_rms:-0}" 'BEGIN { exit !((p + 0) == 0 && (r + 0) == 0) }'; then
        echo "[WARNING] No measurable signal captured from ompx_prg1in_cap (read/capture endpoint). This can indicate missing ALSA routing or inactive source audio."
        echo "[WARNING] Last capture output:"
        tail -n 3 "${test_capture_log}" 2>/dev/null || true
      fi
      rm -f "${test_capture_log}" "${test_inject_log}" || true
    else
      rm -f "${test_wav}" "${test_tone}" || true
      echo "[WARNING] Could not start arecord for loopback self-test"
      echo "[WARNING] Check arecord -L for ompx_prg1in_cap (capture endpoint) and ensure snd_aloop is loaded"
      rm -f "${test_capture_log}" "${test_inject_log}" || true
    fi

    if [ -t 0 ]; then
      echo "[PROMPT] Loopback self-test failed."
      echo "  R) Retry self-test"
      echo "  C) Continue installation"
      echo "  A) Abort installation"
      read -t 60 -p "Select [R/C/A] (default C): " selftest_choice || selftest_choice="C"
      selftest_choice=${selftest_choice^^}
      case "${selftest_choice}" in
        R)
          test_attempt=$((test_attempt + 1))
          continue
          ;;
        A)
          echo "[ERROR] Aborting at user request due to failed loopback self-test"
          exit 1
          ;;
        *)
          echo "[INFO] Continuing installation after failed loopback self-test"
          break
          ;;
      esac
    else
      echo "[INFO] Non-interactive mode: continuing after failed loopback self-test"
      break
    fi
  done
elif [ "${RUN_QUICK_AUDIO_TEST}" = true ]; then
  echo "[INFO] Skipping quick loopback self-test because the live ALSA config is not active yet"
fi
# --- Create FIFOs for ingest/processing pipeline ---
echo "[INFO] Creating FIFOs for radio streams..."

for r in 1 2; do
fifo="${FIFOS_DIR}/radio${r}.pcm"
rm -f "$fifo" || true
mkfifo -m 660 "$fifo"
chown "${OMPX_USER}:${OMPX_USER}" "$fifo"
echo "[SUCCESS] Created FIFO: $fifo"
done
# --- Create source wrapper scripts (persistent ffmpeg ingest to ALSA sinks) ---
echo "[INFO] Creating wrapper scripts..."

for n in 1 2; do
cat > "${SYS_SCRIPTS_DIR}/source${n}.sh" <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
# Prevent multiple instances (one ffmpeg per program source)
SCRIPT_NAME="$(basename "$0")"
if pgrep -f "${SCRIPT_NAME}" | grep -v "^$$$" | grep -q .; then
  echo "[$(date +'%F %T')] ${SCRIPT_NAME}: Another instance is already running. Exiting to prevent duplicate ffmpeg connections."
  exit 0
fi
PROFILE="${OMPX_HOME}/.profile"
[ -f "$PROFILE" ] && . "$PROFILE"
RADIO_VAR_NAME="RADIO${n}_URL"
RADIO_URL_VALUE="${!RADIO_VAR_NAME:-}"
INGEST_DELAY_SEC="${INGEST_DELAY_SEC:-10}"
P1_INGEST_DELAY_SEC="${P1_INGEST_DELAY_SEC:-}"
P2_INGEST_DELAY_SEC="${P2_INGEST_DELAY_SEC:-}"
NON_MPX_SAMPLE_RATE="${NON_MPX_SAMPLE_RATE:-48000}"
PROGRAM2_ENABLED="${PROGRAM2_ENABLED:-false}"
if ! [[ "${INGEST_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  INGEST_DELAY_SEC=10
fi
if [ -n "${P1_INGEST_DELAY_SEC}" ] && ! [[ "${P1_INGEST_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  P1_INGEST_DELAY_SEC=""
fi
if [ -n "${P2_INGEST_DELAY_SEC}" ] && ! [[ "${P2_INGEST_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  P2_INGEST_DELAY_SEC=""
fi
if ! [[ "${NON_MPX_SAMPLE_RATE}" =~ ^[0-9]+$ ]]; then
  NON_MPX_SAMPLE_RATE=48000
fi
PROGRAM2_ENABLED="${PROGRAM2_ENABLED,,}"
if [ "${n}" = "1" ]; then
  SINK_NAME="ompx_prg1in"
  CHANNEL_DELAY_SEC="${P1_INGEST_DELAY_SEC:-${INGEST_DELAY_SEC}}"
else
  SINK_NAME="ompx_prg2in"
  CHANNEL_DELAY_SEC="${P2_INGEST_DELAY_SEC:-${INGEST_DELAY_SEC}}"
  if [ "${PROGRAM2_ENABLED}" != "true" ]; then
    echo "[$(date +'%F %T')] source${n}: PROGRAM2_ENABLED=false; exiting"
    exit 0
  fi
fi
if ! [[ "${CHANNEL_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  CHANNEL_DELAY_SEC=0
fi
INGEST_DELAY_MS=$((CHANNEL_DELAY_SEC * 1000))
if ! aplay -L 2>/dev/null | grep -q "^${SINK_NAME}$"; then
  if [ "${n}" = "1" ]; then
    SINK_NAME="plughw:${LOOPBACK_CARD_REF},0,0"
  else
    SINK_NAME="plughw:${LOOPBACK_CARD_REF},0,1"
  fi
  echo "[$(date +'%F %T')] source${n}: named sink unavailable; using fallback ${SINK_NAME}"
fi
echo "[$(date +'%F %T')] source${n}: using ALSA output endpoint ${SINK_NAME}"
echo "[$(date +'%F %T')] source${n}: ingest via ffmpeg (input format auto-detected, delay ${CHANNEL_DELAY_SEC}s, sink rate ${NON_MPX_SAMPLE_RATE}Hz)"

if [ -z "${RADIO_URL_VALUE}" ] || [[ "${RADIO_URL_VALUE}" == *"example-icecast.local"* ]] || [[ "${RADIO_URL_VALUE}" == *"your.stream/url"* ]]; then
  echo "[$(date +'%F %T')] source${n}: RADIO${n}_URL is empty/placeholder; exiting"
  exit 0
fi

while true :
do
  sleep 5
  ffmpeg -nostdin -reconnect 1 -reconnect_streamed 1 -reconnect_at_eof 1 -reconnect_delay_max 5 -thread_queue_size 10240 -i "${RADIO_URL_VALUE}" \
    -vn -sn -dn \
    -max_delay 5000000 \
    -af "aformat=channel_layouts=stereo,adelay=${INGEST_DELAY_MS}|${INGEST_DELAY_MS}" \
    -ar "${NON_MPX_SAMPLE_RATE}" -ac 2 -f alsa "${SINK_NAME}" || true
done
WRAP
chown "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}/source${n}.sh"
chmod 750 "${SYS_SCRIPTS_DIR}/source${n}.sh"
echo "[SUCCESS] Created source${n}.sh wrapper"
done
# --- Processing script: run_processing_alsa.sh ---
echo "[INFO] Creating processing script..."

cat > "${SYS_SCRIPTS_DIR}/run_processing_alsa.sh" <<'RUNP'
#!/usr/bin/env bash
set -euo pipefail
PROFILE="/home/ompx/.profile"
[ -f "${PROFILE}" ] && . "${PROFILE}"
STEREO_TOOL_CMD="/usr/local/bin/stereo-tool"
SAMPLE_RATE=192000
PROG1_ALSA_IN="${PROG1_ALSA_IN:-ompx_prg1in_cap}"
PROG2_ALSA_IN="${PROG2_ALSA_IN:-ompx_prg2in_cap}"
PROGRAM2_ENABLED="${PROGRAM2_ENABLED:-false}"
SYS_SCRIPTS_DIR="/opt/mpx-radio"
OMPX_LOG_DIR="/home/ompx/logs"
LOOPBACK_CARD_REF="${LOOPBACK_CARD_REF:-}"
MPX_LEFT_MONO="/tmp/mpx_left.pcm"; MPX_RIGHT_MONO="/tmp/mpx_right.pcm"
MPX_LEFT_OUT="${MPX_LEFT_MONO}.out"; MPX_RIGHT_OUT="${MPX_RIGHT_MONO}.out"
MPX_STEREO_FIFO="/tmp/mpx_stereo.pcm"
_log(){ logger -t mpx "$*"; echo "$(date +'%F %T') $*"; }
detect_loopback_card(){
  local card_ref=""
  card_ref=$(aplay -l 2>/dev/null | awk '/\[Loopback\]/{gsub(":", "", $2); print $2; exit}')
  if [ -n "${card_ref}" ]; then echo "${card_ref}"; return 0; fi
  card_ref=$(awk -F'[][]' '/Loopback/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); split($1, a, /[[:space:]]+/); print a[1]; exit}' /proc/asound/cards 2>/dev/null)
  if [ -n "${card_ref}" ]; then echo "${card_ref}"; return 0; fi
  echo "Loopback"
}
wait_for_alsa_endpoint(){
  local mode="$1"
  local endpoint="$2"
  local timeout_sec="${3:-30}"
  local waited=0
  while [ "${waited}" -lt "${timeout_sec}" ]; do
    if [ "${mode}" = "capture" ]; then
      if arecord -L 2>/dev/null | grep -q "^${endpoint}$"; then return 0; fi
    else
      if aplay -L 2>/dev/null | grep -q "^${endpoint}$"; then return 0; fi
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}
mkdir -p "${OMPX_LOG_DIR}" || true
if [ -z "${LOOPBACK_CARD_REF}" ]; then
  LOOPBACK_CARD_REF="$(detect_loopback_card)"
  _log "Auto-detected loopback card: ${LOOPBACK_CARD_REF}"
fi
PROGRAM2_ENABLED="${PROGRAM2_ENABLED,,}"

for n in 1 2; do
  wrapper="${SYS_SCRIPTS_DIR}/source${n}.sh"
  log_file="${OMPX_LOG_DIR}/radio-source${n}.log"
  if [ -x "${wrapper}" ] && ! pgrep -f "${wrapper}" >/dev/null 2>&1; then
    nohup "${wrapper}" >>"${log_file}" 2>&1 &
    _log "Started ${wrapper} for upstream ingest"
  fi
done

wait_for_alsa_endpoint capture "${PROG1_ALSA_IN}" 60 || true
if ! arecord -L 2>/dev/null | grep -q "^${PROG1_ALSA_IN}$"; then
  PROG1_ALSA_IN="hw:${LOOPBACK_CARD_REF},1,0"
  _log "Fallback capture endpoint for Program 1: ${PROG1_ALSA_IN}"
fi
if [ "${PROGRAM2_ENABLED}" = "true" ]; then
  wait_for_alsa_endpoint capture "${PROG2_ALSA_IN}" 60 || true
  if ! arecord -L 2>/dev/null | grep -q "^${PROG2_ALSA_IN}$"; then
    PROG2_ALSA_IN="hw:${LOOPBACK_CARD_REF},1,1"
    _log "Fallback capture endpoint for Program 2: ${PROG2_ALSA_IN}"
  fi
else
  PROG2_ALSA_IN=""
  _log "PROGRAM2_ENABLED=false; Program 2 capture disabled"
fi
_log "Using capture endpoints: PROG1_ALSA_IN=${PROG1_ALSA_IN}, PROG2_ALSA_IN=${PROG2_ALSA_IN}"

for p in "$MPX_LEFT_MONO" "$MPX_RIGHT_MONO" "$MPX_LEFT_OUT" "$MPX_RIGHT_OUT" "$MPX_STEREO_FIFO"; do rm -f "$p" || true; mkfifo "$p"; done
ffmpeg -hide_banner -loglevel warning -f alsa -thread_queue_size 10240 -i "${PROG1_ALSA_IN}" -filter_complex "[0:a]pan=mono|c0=0.5*c0+0.5*c1[out]" -map "[out]" -f s16le -ac 1 -ar ${SAMPLE_RATE} - > "${MPX_LEFT_MONO}" &
FF_PROG1_MONO_PID=$!; _log "Spawned PROG1 mono extractor pid $FF_PROG1_MONO_PID"
if [ "${PROGRAM2_ENABLED}" = "true" ] && (arecord -L 2>/dev/null | grep -q "^${PROG2_ALSA_IN}$" || [[ "${PROG2_ALSA_IN}" == hw:Loopback,* ]]); then
ffmpeg -hide_banner -loglevel warning -f alsa -thread_queue_size 10240 -i "${PROG2_ALSA_IN}" -filter_complex "[0:a]pan=mono|c0=0.5*c0+0.5*c1[out]" -map "[out]" -f s16le -ac 1 -ar ${SAMPLE_RATE} - > "${MPX_RIGHT_MONO}" &
FF_PROG2_MONO_PID=$!; _log "Spawned PROG2 mono extractor pid ${FF_PROG2_MONO_PID:-0}"
else
( while :; do dd if=/dev/zero bs=4096 count=256 status=none; sleep 0.1; done ) > "${MPX_RIGHT_MONO}" &
SILENCE_PID=$!
_log "Program 2 not active/available; injecting silence on right channel"
fi
"${STEREO_TOOL_CMD}" --mode live --left-fifo "${MPX_LEFT_MONO}" --right-fifo "${MPX_RIGHT_MONO}" --out-left-fifo "${MPX_LEFT_OUT}" --out-right-fifo "${MPX_RIGHT_OUT}" &
STEREO_PID=$!; _log "Started stereo-tool wrapper pid ${STEREO_PID}"
ffmpeg -hide_banner -loglevel warning -f s16le -ar ${SAMPLE_RATE} -ac 1 -i "${MPX_LEFT_OUT}" -f s16le -ar ${SAMPLE_RATE} -ac 1 -i "${MPX_RIGHT_OUT}" -filter_complex "[0:a][1:a]join=inputs=2:channel_layout=stereo[aout]" -map "[aout]" -f s16le -ar ${SAMPLE_RATE} -ac 2 - > "${MPX_STEREO_FIFO}" &
FF_MERGE_PID=$!; _log "ffmpeg merge pid $FF_MERGE_PID"
ALSA_OUTPUT="${ALSA_OUTPUT:-}"
if [ -z "$ALSA_OUTPUT" ]; then
if wait_for_alsa_endpoint playback "ompx_prg1mpx" 20; then
ALSA_OUTPUT="ompx_prg1mpx"
elif aplay -l 2>/dev/null | grep -qi loopback; then
ALSA_OUTPUT="hw:${LOOPBACK_CARD_REF},0,0"
fi
fi
if [ -z "$ALSA_OUTPUT" ]; then _log "No ALSA output selected."; exit 1; fi
ffmpeg -hide_banner -loglevel warning -f s16le -ar ${SAMPLE_RATE} -ac 2 -i "${MPX_STEREO_FIFO}" -f alsa "${ALSA_OUTPUT}" &
PLAY_PID=$!; _log "MPX playback started (pid ${PLAY_PID:-0})"
wait ${PLAY_PID:-0} || true
kill ${FF_PROG1_MONO_PID:-0} ${FF_PROG2_MONO_PID:-0} ${STEREO_PID:-0} ${FF_MERGE_PID:-0} 2>/dev/null || true
_log "run_processing_alsa.sh exiting"
RUNP
chown "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}/run_processing_alsa.sh"
chmod 750 "${SYS_SCRIPTS_DIR}/run_processing_alsa.sh"
echo "[SUCCESS] Processing script created"

# --- MPX mix + Icecast encoder script ---
echo "[INFO] Creating mpx-mix.sh (mono sum, hard pan, Icecast ffmpeg encoder)..."
cat > "${SYS_SCRIPTS_DIR}/mpx-mix.sh" <<'MPXMIX'
#!/usr/bin/env bash
# mpx-mix.sh — publish MPX stereo to Icecast.
# Default topology uses a single combined stereo source on ST_OUT_P1.
# Optional split-source mode can be enabled by setting ST_OUT_P2.
set -euo pipefail

PROFILE="/home/ompx/.profile"
[ -f "${PROFILE}" ] && . "${PROFILE}"

ICECAST_HOST="${ICECAST_HOST:-127.0.0.1}"
ICECAST_PORT="${ICECAST_PORT:-8000}"
ICECAST_SOURCE_USER="${ICECAST_SOURCE_USER:-source}"
ICECAST_PASSWORD="${ICECAST_PASSWORD:-}"
ICECAST_MOUNT="${ICECAST_MOUNT:-/mpx}"
ICECAST_SAMPLE_RATE="${ICECAST_SAMPLE_RATE:-192000}"
ICECAST_BIT_DEPTH="${ICECAST_BIT_DEPTH:-16}"
ICECAST_CODEC="flac"
ICECAST_MODE="${ICECAST_MODE:-disabled}"
ICECAST_INPUT_MODE="${ICECAST_INPUT_MODE:-auto}"
ST_OUT_P1="${ST_OUT_P1:-ompx_prg1mpx_cap}"
ST_OUT_P2="${ST_OUT_P2:-}"
RADIO1_URL="${RADIO1_URL:-}"
RADIO2_URL="${RADIO2_URL:-}"
PROGRAM2_ENABLED="${PROGRAM2_ENABLED:-false}"
OMPX_LOG_DIR="/home/ompx/logs"

is_placeholder_stream_url(){
  local u="$1"
  [ -z "${u}" ] && return 0
  case "${u}" in
    *example-icecast.local*|*your.stream/url*) return 0 ;;
  esac
  return 1
}

mkdir -p "${OMPX_LOG_DIR}"
_log(){ logger -t mpx-mix "$*"; echo "$(date +'%F %T') [mpx-mix] $*"; }

if [ -z "${ICECAST_PASSWORD}" ]; then
  if command -v openssl >/dev/null 2>&1; then
    ICECAST_PASSWORD="$(openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 24 || true)"
  fi
  if [ -z "${ICECAST_PASSWORD}" ]; then
    ICECAST_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)"
  fi
  if [ -z "${ICECAST_PASSWORD}" ]; then
    ICECAST_PASSWORD="ompx$(date +%s)"
  fi
  _log "ICECAST_PASSWORD not set; generated runtime password"
fi

if [ "${ICECAST_MODE}" = "disabled" ]; then
  _log "ICECAST_MODE=disabled — mpx-mix is not configured. Set ICECAST_MODE in /home/ompx/.profile and restart."
  exit 0
fi

wait_alsa_cap(){
  local dev="$1" timeout=30 waited=0
  while [ "${waited}" -lt "${timeout}" ]; do
    arecord -L 2>/dev/null | grep -q "^${dev}$" && return 0
    sleep 1; waited=$((waited+1))
  done
  return 1
}

P2_AVAILABLE=0
PROGRAM2_ENABLED="${PROGRAM2_ENABLED,,}"
if [ "${ICECAST_INPUT_MODE}" != "direct_urls" ]; then
  _log "Waiting for ST output endpoints..."
  wait_alsa_cap "${ST_OUT_P1}" || { _log "ERROR: ${ST_OUT_P1} not available"; exit 1; }
  if [ -n "${ST_OUT_P2}" ] && [ "${PROGRAM2_ENABLED}" = "true" ]; then
    if arecord -L 2>/dev/null | grep -q "^${ST_OUT_P2}$"; then
      P2_AVAILABLE=1
    fi
  fi
  _log "P1 source: ${ST_OUT_P1}"
  _log "P2 source: ${ST_OUT_P2} (enabled: ${PROGRAM2_ENABLED}, available: ${P2_AVAILABLE})"
fi
if [ "${ICECAST_BIT_DEPTH}" = "24" ]; then
  FLAC_SAMPLE_FMT="s32"
  FLAC_BITS_PER_RAW="24"
else
  FLAC_SAMPLE_FMT="s16"
  FLAC_BITS_PER_RAW="16"
  ICECAST_BIT_DEPTH="16"
fi
_log "Icecast: FLAC-in-Ogg ${ICECAST_SAMPLE_RATE}Hz ${ICECAST_BIT_DEPTH}-bit → icecast://${ICECAST_HOST}:${ICECAST_PORT}${ICECAST_MOUNT}"

CODEC_ARGS=(-c:a flac -compression_level 8 -sample_fmt "${FLAC_SAMPLE_FMT}" -bits_per_raw_sample "${FLAC_BITS_PER_RAW}" -content_type audio/ogg -f ogg)

ICECAST_INPUT_MODE="${ICECAST_INPUT_MODE,,}"
if [ "${ICECAST_INPUT_MODE}" = "auto" ]; then
  if [ "${PROGRAM2_ENABLED}" = "true" ] && ! is_placeholder_stream_url "${RADIO1_URL}" && ! is_placeholder_stream_url "${RADIO2_URL}"; then
    ICECAST_INPUT_MODE="direct_urls"
  else
    ICECAST_INPUT_MODE="alsa"
  fi
fi
_log "Input mode: ${ICECAST_INPUT_MODE}"

if [ "${ICECAST_INPUT_MODE}" = "direct_urls" ]; then
  if [ -z "${RADIO1_URL}" ] || [ -z "${RADIO2_URL}" ]; then
    _log "ERROR: ICECAST_INPUT_MODE=direct_urls requires RADIO1_URL and RADIO2_URL"
    exit 1
  fi
  _log "Input mode: direct_urls (RADIO1_URL -> L, RADIO2_URL -> R)"
  exec ffmpeg -nostdin \
    -reconnect 1 -reconnect_streamed 1 -reconnect_at_eof 1 -reconnect_delay_max 5 -thread_queue_size 16384 -i "${RADIO1_URL}" \
    -reconnect 1 -reconnect_streamed 1 -reconnect_at_eof 1 -reconnect_delay_max 5 -thread_queue_size 16384 -i "${RADIO2_URL}" \
    -filter_complex \
      "[0:a]pan=mono|c0=0.5*c0+0.5*c1[p1];\
       [1:a]pan=mono|c0=0.5*c0+0.5*c1[p2];\
       [p1][p2]join=inputs=2:channel_layout=stereo:map=0.0-FL|1.0-FR[st];\
       [st]aresample=${ICECAST_SAMPLE_RATE}[out]" \
    -map "[out]" \
    -ice_name "oMPX Stereo 192k" \
    -ice_description "Direct dual URL mode: RADIO1_URL (L) + RADIO2_URL (R)" \
    "${CODEC_ARGS[@]}" \
    "icecast://${ICECAST_SOURCE_USER}:${ICECAST_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}${ICECAST_MOUNT}"
fi

if [ "${P2_AVAILABLE}" -eq 1 ]; then
  # Optional split-source mode: P1 mono -> L, P2 mono -> R
  exec ffmpeg -nostdin \
    -f alsa -thread_queue_size 16384 -i "${ST_OUT_P1}" \
    -f alsa -thread_queue_size 16384 -i "${ST_OUT_P2}" \
    -filter_complex \
      "[0:a]pan=mono|c0=c0,aresample=${ICECAST_SAMPLE_RATE}[p1];\
       [1:a]pan=mono|c0=c0,aresample=${ICECAST_SAMPLE_RATE}[p2];\
       [p1][p2]join=inputs=2:channel_layout=stereo:map=0.0-FL|1.0-FR[out]" \
    -map "[out]" \
    -ice_name "oMPX Stereo 192k" \
    -ice_description "P1 ch0 (L) + P2 ch0 (R), hard-panned" \
    "${CODEC_ARGS[@]}" \
    "icecast://${ICECAST_SOURCE_USER}:${ICECAST_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}${ICECAST_MOUNT}"
else
  # Default mode: publish the combined stereo MPX path as-is.
  _log "Using P1 stereo source only"
  exec ffmpeg -nostdin \
    -f alsa -thread_queue_size 16384 -i "${ST_OUT_P1}" \
    -af "aresample=${ICECAST_SAMPLE_RATE}" \
    -map 0:a \
    -ice_name "oMPX Stereo 192k" \
    -ice_description "P1 stereo passthrough (P2 not configured)" \
    "${CODEC_ARGS[@]}" \
    "icecast://${ICECAST_SOURCE_USER}:${ICECAST_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}${ICECAST_MOUNT}"
fi
MPXMIX
chown "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}/mpx-mix.sh"
chmod 750 "${SYS_SCRIPTS_DIR}/mpx-mix.sh"
echo "[SUCCESS] Created ${SYS_SCRIPTS_DIR}/mpx-mix.sh"

# --- systemd units ---
echo "[INFO] Creating systemd service files..."

cat > "${SYSTEMD_DIR}/mpx-processing-alsa.service" <<EOF
[Unit]
Description=MPX processing (ALSA/ffmpeg) (oMPX)
After=network-online.target
After=sound.target
Wants=sound.target

[Service]
Type=simple
User=${OMPX_USER}
Group=${OMPX_USER}
SupplementaryGroups=audio
PermissionsStartOnly=true
WorkingDirectory=${OMPX_HOME}
Environment=HOME=${OMPX_HOME}
ExecStartPre=/bin/sh -c 'usermod -aG audio ${OMPX_USER} >/dev/null 2>&1 || true'
ExecStartPre=/bin/sh -c 'if command -v udevadm >/dev/null 2>&1; then udevadm control --reload-rules >/dev/null 2>&1 || true; udevadm trigger --subsystem-match=sound >/dev/null 2>&1 || true; fi'
ExecStartPre=/bin/sh -c 'if [ -d /dev/snd ]; then chgrp -R audio /dev/snd >/dev/null 2>&1 || true; chmod -R g+rw /dev/snd >/dev/null 2>&1 || true; fi'
ExecStartPre=/bin/sh -c 'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do [ -d /dev/snd ] && ls -A /dev/snd >/dev/null 2>&1 && exit 0; sleep 1; done; exit 0'
ExecStartPre=/bin/sh -c 'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do runuser -u ${OMPX_USER} -- aplay -l >/dev/null 2>&1 && exit 0; sleep 1; done; exit 0'
ExecStart=${SYS_SCRIPTS_DIR}/run_processing_alsa.sh
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

mpx_mix_after="network-online.target sound.target"
mpx_mix_wants="network-online.target sound.target"
if [ "${OMPX_STEREO_BACKEND}" = "stereotool" ]; then
  mpx_mix_after="network-online.target stereo-tool-enterprise.service sound.target"
  mpx_mix_wants="network-online.target stereo-tool-enterprise.service sound.target"
fi

cat > "${SYSTEMD_DIR}/mpx-mix.service" <<EOF
[Unit]
Description=oMPX MPX mix — mono sum / hard pan / Icecast FLAC encoder
After=${mpx_mix_after}
Wants=${mpx_mix_wants}

[Service]
Type=simple
User=${OMPX_USER}
Group=${OMPX_USER}
SupplementaryGroups=audio
PermissionsStartOnly=true
WorkingDirectory=${OMPX_HOME}
Environment=HOME=${OMPX_HOME}
ExecStartPre=/bin/sh -c 'if [ -d /dev/snd ]; then chgrp -R audio /dev/snd >/dev/null 2>&1 || true; chmod -R g+rw /dev/snd >/dev/null 2>&1 || true; fi'
ExecStart=${SYS_SCRIPTS_DIR}/mpx-mix.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "${SYSTEMD_DIR}/mpx-mix.service"
chown root:root "${SYSTEMD_DIR}/mpx-mix.service"
echo "[SUCCESS] Installed mpx-mix.service"

cat > "${SYSTEMD_DIR}/mpx-watchdog.service" <<EOF
[Unit]
Description=MPX watchdog to ensure processing service is running
After=network-online.target
[Service]
User=${OMPX_USER}
Group=${OMPX_USER}
Type=simple
ExecStart=${SYS_SCRIPTS_DIR}/mpx-watchdog.sh
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF

cat > "${OMPX_STREAM_PULL_SERVICE}" <<EOF
[Unit]
Description=MPX stream pull bootstrap
After=network-online.target sound.target
Wants=network-online.target sound.target

[Service]
Type=oneshot
User=root
Group=root
ExecStart=${SYS_SCRIPTS_DIR}/start_or_shell.sh --start
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

cat > "${OMPX_SOURCE1_SERVICE}" <<EOF
[Unit]
Description=oMPX upstream ingest source1
After=network-online.target sound.target
Wants=network-online.target sound.target

[Service]
Type=simple
User=${OMPX_USER}
Group=${OMPX_USER}
SupplementaryGroups=audio
WorkingDirectory=${OMPX_HOME}
Environment=HOME=${OMPX_HOME}
ExecStart=${SYS_SCRIPTS_DIR}/source1.sh
Restart=on-failure
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

cat > "${OMPX_SOURCE2_SERVICE}" <<EOF
[Unit]
Description=oMPX upstream ingest source2
After=network-online.target sound.target
Wants=network-online.target sound.target

[Service]
Type=simple
User=${OMPX_USER}
Group=${OMPX_USER}
SupplementaryGroups=audio
WorkingDirectory=${OMPX_HOME}
Environment=HOME=${OMPX_HOME}
ExecStart=${SYS_SCRIPTS_DIR}/source2.sh
Restart=on-failure
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

cat > "${SYS_SCRIPTS_DIR}/mpx-watchdog.sh" <<'WD'
#!/usr/bin/env bash
set -euo pipefail
SLEEP=5
while true; do
if ! systemctl is-active --quiet mpx-processing-alsa.service; then
logger -t mpx "Watchdog: restarting processing service"
systemctl restart mpx-processing-alsa.service || logger -t mpx "Watchdog: failed to restart"
fi
if systemctl list-unit-files | grep -q '^stereo-tool-enterprise.service'; then
if ! systemctl is-active --quiet stereo-tool-enterprise.service; then
st_result="$(systemctl show -p Result --value stereo-tool-enterprise.service 2>/dev/null || true)"
if [ "${st_result}" = "start-limit-hit" ]; then
logger -t mpx "Watchdog: stereo-tool-enterprise.service is rate-limited by systemd (start-limit-hit); waiting for interval"
else
logger -t mpx "Watchdog: restarting stereo-tool-enterprise.service"
systemctl restart stereo-tool-enterprise.service || logger -t mpx "Watchdog: failed to restart stereo-tool-enterprise.service"
fi
fi
fi
sleep $SLEEP
done
WD
chown "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}/mpx-watchdog.sh"
chmod 750 "${SYS_SCRIPTS_DIR}/mpx-watchdog.sh"
echo "[SUCCESS] Systemd service files created"
# --- stereo-tool wrapper & checker ---
echo "[INFO] Creating stereo-tool wrapper..."

cat > /usr/local/bin/ompx-stereo-rds-wrapper <<'OMPXWRAP'
#!/usr/bin/env bash
set -euo pipefail

PROFILE="/home/ompx/.profile"
[ -f "${PROFILE}" ] && . "${PROFILE}"

LEFT_IN=""; RIGHT_IN=""; LEFT_OUT=""; RIGHT_OUT=""
SAMPLE_RATE="${OMPX_WRAPPER_SAMPLE_RATE:-192000}"
PILOT_LEVEL="${OMPX_WRAPPER_PILOT_LEVEL:-0.09}"
RDS_LEVEL="${OMPX_WRAPPER_RDS_LEVEL:-0.03}"
WRAPPER_PRESET="${OMPX_WRAPPER_PRESET:-balanced}"
FM_PREEMPHASIS="${OMPX_FM_PREEMPHASIS:-75}"
LMR_GAIN="1.0"
ENABLE_RDS="${OMPX_WRAPPER_RDS_ENABLE:-false}"
RDS_ENCODER_CMD="${OMPX_WRAPPER_RDS_ENCODER_CMD:-}"

case "${WRAPPER_PRESET,,}" in
  conservative)
    PILOT_LEVEL="0.085"
    RDS_LEVEL="0.020"
    LMR_GAIN="0.92"
    ;;
  hot)
    PILOT_LEVEL="0.100"
    RDS_LEVEL="0.040"
    LMR_GAIN="1.10"
    ;;
  speech)
    PILOT_LEVEL="0.090"
    RDS_LEVEL="0.025"
    LMR_GAIN="0.88"
    ;;
  *)
    ;;
esac

PREEMPH_FILTER_L="anull"
PREEMPH_FILTER_R="anull"
case "${FM_PREEMPHASIS,,}" in
  75|75us)
    # 75 us preemphasis approximation for FM chains using a high-shelf tilt.
    PREEMPH_FILTER_L="highshelf=f=2122:g=13"
    PREEMPH_FILTER_R="highshelf=f=2122:g=13"
    ;;
  50|50us)
    # 50 us preemphasis approximation for FM chains using a high-shelf tilt.
    PREEMPH_FILTER_L="highshelf=f=3183:g=10"
    PREEMPH_FILTER_R="highshelf=f=3183:g=10"
    ;;
  *)
    ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --left-fifo) LEFT_IN="$2"; shift 2 ;;
    --right-fifo) RIGHT_IN="$2"; shift 2 ;;
    --out-left-fifo) LEFT_OUT="$2"; shift 2 ;;
    --out-right-fifo) RIGHT_OUT="$2"; shift 2 ;;
    --mode) shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "${LEFT_IN}" ] || [ -z "${RIGHT_IN}" ] || [ -z "${LEFT_OUT}" ] || [ -z "${RIGHT_OUT}" ]; then
  echo "ompx-stereo-rds-wrapper: missing fifo arguments" >&2
  exit 2
fi

RDS_INPUT_SPEC=(-f lavfi -i "anullsrc=r=${SAMPLE_RATE}:cl=mono")
RDS_FILTER_CHAIN="[4:a]anull[rds]"
if [ "${ENABLE_RDS,,}" = "true" ] && [ -n "${RDS_ENCODER_CMD}" ]; then
  RDS_FIFO="/tmp/ompx_rds_subcarrier.pcm"
  rm -f "${RDS_FIFO}" || true
  mkfifo "${RDS_FIFO}"
  sh -c "${RDS_ENCODER_CMD}" > "${RDS_FIFO}" 2>/tmp/ompx_rds_encoder.log &
  RDS_ENCODER_PID=$!
  trap 'kill ${RDS_ENCODER_PID:-0} 2>/dev/null || true; rm -f "${RDS_FIFO}"' EXIT
  RDS_INPUT_SPEC=(-f s16le -ar "${SAMPLE_RATE}" -ac 1 -i "${RDS_FIFO}")
  RDS_FILTER_CHAIN="[4:a]aformat=sample_fmts=fltp:sample_rates=${SAMPLE_RATE}:channel_layouts=mono[rds]"
fi

exec ffmpeg -hide_banner -loglevel warning -nostdin -y \
  -f s16le -ar "${SAMPLE_RATE}" -ac 1 -i "${LEFT_IN}" \
  -f s16le -ar "${SAMPLE_RATE}" -ac 1 -i "${RIGHT_IN}" \
  -f lavfi -i "aevalsrc=${PILOT_LEVEL}*sin(2*PI*19000*t):s=${SAMPLE_RATE}" \
  -f lavfi -i "aevalsrc=sin(2*PI*38000*t):s=${SAMPLE_RATE}" \
  "${RDS_INPUT_SPEC[@]}" \
  -filter_complex "[0:a]${PREEMPH_FILTER_L}[lin]; \
    [1:a]${PREEMPH_FILTER_R}[rin]; \
    [lin][rin]join=inputs=2:channel_layout=stereo[st]; \
    [st]pan=mono|c0=0.5*c0+0.5*c1[lpr]; \
    [st]pan=mono|c0=0.5*c0-0.5*c1[lmr]; \
    [lmr]volume=${LMR_GAIN}[lmrv]; \
    [lmrv][3:a]amultiply[dsb]; \
    ${RDS_FILTER_CHAIN}; \
    [rds]volume=${RDS_LEVEL}[rdsv]; \
    [lpr][dsb][2:a][rdsv]amix=inputs=4:normalize=0[mpx]; \
    [mpx]asplit=2[outl][outr]" \
  -map "[outl]" -f s16le "${LEFT_OUT}" \
  -map "[outr]" -f s16le "${RIGHT_OUT}"
OMPXWRAP
chmod 755 /usr/local/bin/ompx-stereo-rds-wrapper
chown root:root /usr/local/bin/ompx-stereo-rds-wrapper

cat > "${STEREO_TOOL_WRAPPER}.real-check" <<'CHECK'
#!/usr/bin/env bash
path=$(command -v stereo-tool 2>/dev/null || true)
if [ -z "$path" ]; then exit 2; fi
if stereo-tool --help 2>&1 | grep -q -- '--left-fifo'; then echo "$path"; exit 0; fi
exit 3
CHECK
chmod +x "${STEREO_TOOL_WRAPPER}.real-check"

cat > "${STEREO_TOOL_WRAPPER}" <<'WRAPST'
#!/usr/bin/env bash
set -euo pipefail
PROFILE="/home/ompx/.profile"
[ -f "${PROFILE}" ] && . "${PROFILE}"
BACKEND="${OMPX_STEREO_BACKEND:-ompx-mpx}"
BACKEND="${BACKEND,,}"
if [ "${BACKEND}" = "stereotool" ]; then
  if /usr/local/bin/stereo-tool.real-check >/dev/null 2>&1; then
    exec stereo-tool "$@"
  fi
  echo "stereo-tool wrapper: backend=stereotool requested, but binary unavailable; falling back to ompx-mpx" >&2
  BACKEND="ompx-mpx"
fi
if [ "${BACKEND}" = "ompx-mpx" ]; then
  exec /usr/local/bin/ompx-stereo-rds-wrapper "$@"
fi
if [ "${BACKEND}" = "passthrough" ]; then
  LEFT_IN=""; RIGHT_IN=""; LEFT_OUT=""; RIGHT_OUT=""
  while [ $# -gt 0 ]; do case "$1" in --left-fifo) LEFT_IN="$2"; shift 2;; --right-fifo) RIGHT_IN="$2"; shift 2;; --out-left-fifo) LEFT_OUT="$2"; shift 2;; --out-right-fifo) RIGHT_OUT="$2"; shift 2;; *) shift;; esac; done
  if [ -n "$LEFT_IN" ] && [ -n "$LEFT_OUT" ]; then ( while :; do dd if="$LEFT_IN" of="$LEFT_OUT" bs=4096 status=none || sleep 1; done ) & fi
  if [ -n "$RIGHT_IN" ] && [ -n "$RIGHT_OUT" ]; then ( while :; do dd if="$RIGHT_IN" of="$RIGHT_OUT" bs=4096 status=none || sleep 1; done ) & fi
  wait
  exit 0
fi
echo "stereo-tool wrapper: invalid OMPX_STEREO_BACKEND='${BACKEND}'" >&2
exit 2
WRAPST
chmod 755 "${STEREO_TOOL_WRAPPER}" "${STEREO_TOOL_WRAPPER}.real-check"
chown root:root "${STEREO_TOOL_WRAPPER}" "${STEREO_TOOL_WRAPPER}.real-check"
echo "[SUCCESS] Stereo-tool wrapper created"
# --- ompx_add_source helper (persist radio URL, create wrapper, setup cron) ---
echo "[INFO] Creating ompx_add_source helper..."

cat > "${OMPX_ADD}" <<'ADD'
#!/usr/bin/env bash
set -euo pipefail
SYS_SCRIPTS_DIR="/opt/mpx-radio"; OMPX_USER="ompx"; OMPX_HOME="/home/ompx"; OMPX_LOG_DIR="${OMPX_HOME}/logs"; CRON_SLEEP=10
detect_loopback_card_ref(){
  local card_ref=""
  card_ref=$(aplay -l 2>/dev/null | awk '/\[Loopback\]/{gsub(":", "", $2); print $2; exit}')
  if [ -n "$card_ref" ]; then
    echo "$card_ref"
    return 0
  fi
  card_ref=$(awk -F'[][]' '/Loopback/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); split($1, a, /[[:space:]]+/); print a[1]; exit}' /proc/asound/cards 2>/dev/null)
  if [ -n "$card_ref" ]; then
    echo "$card_ref"
    return 0
  fi
  echo "Loopback"
}
LOOPBACK_CARD_REF="${LOOPBACK_CARD_REF:-$(detect_loopback_card_ref)}"
usage(){ cat <<USAGE
Usage: $0 --radio 1|2 --url URL [--cron-user root|ompx] [--start-now]
Adds or updates an existing radio source URL and wrapper.
USAGE
}
RADIO=""; URL=""; CRON_USER="${OMPX_USER}"; START_NOW=0
while [ $# -gt 0 ]; do case "$1" in --radio) RADIO="$2"; shift 2;; --url) URL="$2"; shift 2;; --cron-user) CRON_USER="$2"; shift 2;; --start-now) START_NOW=1; shift;; -h|--help) usage; exit 0;; *) echo "Unknown arg: $1"; usage; exit 1;; esac; done
if [ -z "$RADIO" ] || [ -z "$URL" ]; then usage; exit 1; fi
PROFILE="${OMPX_HOME}/.profile"; cp -a "$PROFILE" "${PROFILE}.bak.$(date +%s)"
VAR="RADIO${RADIO}_URL"
if grep -q "^${VAR}=" "$PROFILE"; then sed -i "s|^${VAR}=.*|${VAR}=\"${URL}\"|" "$PROFILE"; else echo "${VAR}=\"${URL}\"" >> "$PROFILE"; fi
if grep -q '^STREAM_ENGINE=' "$PROFILE"; then sed -i 's|^STREAM_ENGINE=.*|STREAM_ENGINE="ffmpeg"|' "$PROFILE"; else echo 'STREAM_ENGINE="ffmpeg"' >> "$PROFILE"; fi
chown ${OMPX_USER}:${OMPX_USER} "$PROFILE"; chmod 644 "$PROFILE"
WRAPPER="${SYS_SCRIPTS_DIR}/source${RADIO}.sh"
LOG_FILE="${OMPX_LOG_DIR}/radio-source${RADIO}.log"
mkdir -p "${OMPX_LOG_DIR}"
touch "${LOG_FILE}"
chown "${OMPX_USER}:${OMPX_USER}" "${OMPX_LOG_DIR}" "${LOG_FILE}"
chmod 755 "${OMPX_LOG_DIR}"
chmod 664 "${LOG_FILE}"
cat > "$WRAPPER" <<WRAP
#!/usr/bin/env bash
set -euo pipefail
PROFILE="${OMPX_HOME}/.profile"
[ -f "$PROFILE" ] && . "$PROFILE"
RADIO_VAR_NAME="RADIO${RADIO}_URL"
RADIO_URL_VALUE="\${!RADIO_VAR_NAME:-}"
INGEST_DELAY_SEC="\${INGEST_DELAY_SEC:-10}"
P1_INGEST_DELAY_SEC="\${P1_INGEST_DELAY_SEC:-}"
P2_INGEST_DELAY_SEC="\${P2_INGEST_DELAY_SEC:-}"
if ! [[ "\${INGEST_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  INGEST_DELAY_SEC=10
fi
if [ -n "\${P1_INGEST_DELAY_SEC}" ] && ! [[ "\${P1_INGEST_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  P1_INGEST_DELAY_SEC=""
fi
if [ -n "\${P2_INGEST_DELAY_SEC}" ] && ! [[ "\${P2_INGEST_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  P2_INGEST_DELAY_SEC=""
fi
if [ "${RADIO}" = "1" ]; then
  SINK_NAME="ompx_prg1in"
  CHANNEL_DELAY_SEC="\${P1_INGEST_DELAY_SEC:-\${INGEST_DELAY_SEC}}"
else
  SINK_NAME="ompx_prg2in"
  CHANNEL_DELAY_SEC="\${P2_INGEST_DELAY_SEC:-\${INGEST_DELAY_SEC}}"
fi
if ! [[ "\${CHANNEL_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  CHANNEL_DELAY_SEC=0
fi
INGEST_DELAY_MS=\$((CHANNEL_DELAY_SEC * 1000))
if ! aplay -L 2>/dev/null | grep -q "^\${SINK_NAME}$"; then
  if [ "${RADIO}" = "1" ]; then
    SINK_NAME="plughw:${LOOPBACK_CARD_REF},0,0"
  else
    SINK_NAME="plughw:${LOOPBACK_CARD_REF},0,1"
  fi
  echo "[\$(date +'%F %T')] source${RADIO}: named sink unavailable; using fallback \${SINK_NAME}"
fi
echo "[\$(date +'%F %T')] source${RADIO}: using ALSA output endpoint \${SINK_NAME}"
echo "[\$(date +'%F %T')] source${RADIO}: ingest via ffmpeg (input format auto-detected, delay \${CHANNEL_DELAY_SEC}s)"
if [ -z "\${RADIO_URL_VALUE}" ] || [[ "\${RADIO_URL_VALUE}" == *"example-icecast.local"* ]] || [[ "\${RADIO_URL_VALUE}" == *"your.stream/url"* ]]; then
  echo "[\$(date +'%F %T')] source${RADIO}: RADIO${RADIO}_URL is empty/placeholder; exiting"
  exit 0
fi
while true :
do
  sleep 5
  ffmpeg -nostdin -reconnect 1 -reconnect_streamed 1 -reconnect_at_eof 1 -reconnect_delay_max 5 \
    -thread_queue_size 10240 -i "\${RADIO_URL_VALUE}" \
    -vn -sn -dn \
    -max_delay 5000000 \
    -af "aformat=channel_layouts=stereo,adelay=\${INGEST_DELAY_MS}|\${INGEST_DELAY_MS}" \
    -ar 192000 -ac 2 -f alsa "\${SINK_NAME}" || true
done
WRAP
chown ${OMPX_USER}:${OMPX_USER} "$WRAPPER"; chmod 750 "$WRAPPER"
CRON_CMD="@reboot sleep ${CRON_SLEEP} && ${WRAPPER} >>${LOG_FILE} 2>&1 &"
if command -v crontab >/dev/null 2>&1; then
  ( crontab -u "$CRON_USER" -l 2>/dev/null || true; echo "${CRON_CMD}" ) | crontab -u "$CRON_USER" -
else
  echo "WARNING: crontab command not found; skipping cron setup for $CRON_USER" >&2
fi
if [ "${START_NOW}" -eq 1 ]; then
if [ "$CRON_USER" = "root" ]; then
  nohup "${WRAPPER}" >>"${LOG_FILE}" 2>&1 &
else
  su -s /bin/sh -c "nohup '${WRAPPER}' >>'${LOG_FILE}' 2>&1 &" "${CRON_USER}"
fi
fi
echo "Updated ${VAR} in ${PROFILE} and ensured cron @reboot for ${CRON_USER}."
ADD
chmod 750 "${OMPX_ADD}"
chown root:root "${OMPX_ADD}"
echo "[SUCCESS] ompx_add_source helper created"

if [ "${AUTO_UPDATE_STREAM_URLS_FROM_HEADER}" = true ]; then
  echo "[INFO] AUTO_UPDATE_STREAM_URLS_FROM_HEADER=true; syncing stream URLs from installer header..."
  for n in 1 2; do
    url_var="RADIO${n}_URL"
    url_val="${!url_var}"
    if [ -z "${url_val}" ] || [[ "${url_val}" == *"example-icecast.local"* ]] || [[ "${url_val}" == *"your.stream/url"* ]]; then
      echo "[INFO] ${url_var} is placeholder/empty; skipping auto-update"
      continue
    fi
    add_args=(--radio "${n}" --url "${url_val}" --cron-user "${OMPX_USER}")
    if [ "${AUTO_START_STREAMS_FROM_HEADER}" = true ]; then
      add_args+=(--start-now)
    fi
    "${OMPX_ADD}" "${add_args[@]}"
    echo "[SUCCESS] Synced ${url_var} via ${OMPX_ADD}"
  done
else
  echo "[INFO] AUTO_UPDATE_STREAM_URLS_FROM_HEADER=false; skipping header stream sync"
fi
if [ "${AUTO_START_STREAMS_FROM_HEADER}" = true ]; then
  echo "[INFO] Header stream URLs are configured to auto-start immediately when valid."
else
  echo "[INFO] Header stream URLs are configured to start on reboot/manual start only."
fi
# --- start_or_shell wrapper ---
echo "[INFO] Creating start_or_shell wrapper..."

cat > "${SYS_SCRIPTS_DIR}/start_or_shell.sh" <<'STARTSH'
#!/usr/bin/env bash
set -euo pipefail

OMPX_USER="ompx"
SYS_SCRIPTS_DIR="/opt/mpx-radio"
OMPX_LOG_DIR="/home/ompx/logs"

usage(){ cat <<USAGE
Usage: $0 [--start] [--shell]
--start   Ensure source1.sh and source2.sh are running (background, logs)
--shell   Drop to an interactive shell as ompx (equivalent to su - ompx)
If neither flag given, acts as --start.
USAGE
}

start_sources(){
mkdir -p "${OMPX_LOG_DIR}"
chown "${OMPX_USER}:${OMPX_USER}" "${OMPX_LOG_DIR}" 2>/dev/null || true
for n in 1 2; do
wrapper="${SYS_SCRIPTS_DIR}/source${n}.sh"
log="${OMPX_LOG_DIR}/radio-source${n}.log"
touch "${log}" 2>/dev/null || true
chown "${OMPX_USER}:${OMPX_USER}" "${log}" 2>/dev/null || true
if ! pgrep -f "${wrapper}" >/dev/null 2>&1; then
su -s /bin/sh -c "nohup '${wrapper}' >>'${log}' 2>&1 &" "${OMPX_USER}"
fi
done
}

case "${1:-}" in
--help|-h) usage; exit 0;;
--shell) exec su - "${OMPX_USER}";;
--start) start_sources;;
"") start_sources;;
*) usage; exit 1;;
esac
STARTSH
chmod 750 "${SYS_SCRIPTS_DIR}/start_or_shell.sh"
chown root:root "${SYS_SCRIPTS_DIR}/start_or_shell.sh"
echo "[SUCCESS] start_or_shell wrapper created"

# --- oMPX web UI service ---
echo "[INFO] Creating oMPX web UI service..."
cat > "${SYS_SCRIPTS_DIR}/ompx-web-ui.py" <<'OMPXWEB'
#!/usr/bin/env python3
import base64
import ipaddress
import json
import os
import signal
import subprocess
import threading
import urllib.parse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROFILE_PATH = "/home/ompx/.profile"
STATE_PATH = "/home/ompx/ompx-webui-state.json"


def parse_profile(path):
  data = {}
  if not os.path.exists(path):
    return data
  with open(path, "r", encoding="utf-8") as f:
    for raw in f:
      line = raw.strip()
      if not line or line.startswith("#") or "=" not in line:
        continue
      k, v = line.split("=", 1)
      v = v.strip().strip('"')
      data[k.strip()] = v
  return data


ENV = parse_profile(PROFILE_PATH)
BIND = ENV.get("OMPX_WEB_BIND", "0.0.0.0")
PORT = int(ENV.get("OMPX_WEB_PORT", "8082"))
WHITELIST_RAW = ENV.get("OMPX_WEB_WHITELIST", "127.0.0.1/32")
AUTH_ENABLE = ENV.get("OMPX_WEB_AUTH_ENABLE", "false").lower() == "true"
AUTH_USER = ENV.get("OMPX_WEB_AUTH_USER", "ompx")
AUTH_PASSWORD = ENV.get("OMPX_WEB_AUTH_PASSWORD", "")
RDS_PROG1_RT_PATH = ENV.get("RDS_PROG1_RT_PATH", "/home/ompx/rds/prog1/rt.txt")
RDS_PROG2_RT_PATH = ENV.get("RDS_PROG2_RT_PATH", "/home/ompx/rds/prog2/rt.txt")
RDS_PROG1_INFO_PATH = ENV.get("RDS_PROG1_INFO_PATH", "/home/ompx/rds/prog1/rds-info.json")
RDS_PROG2_INFO_PATH = ENV.get("RDS_PROG2_INFO_PATH", "/home/ompx/rds/prog2/rds-info.json")
RDS_PROG1_OVERRIDE_PATH = ENV.get("RDS_PROG1_OVERRIDE_PATH", "/home/ompx/rds/prog1/rds-override.json")
RDS_PROG2_OVERRIDE_PATH = ENV.get("RDS_PROG2_OVERRIDE_PATH", "/home/ompx/rds/prog2/rds-override.json")
RADIO1_URL = ENV.get("RADIO1_URL", "")
RADIO2_URL = ENV.get("RADIO2_URL", "")

ALLOWED_NETWORKS = []
for token in WHITELIST_RAW.split(","):
  token = token.strip()
  if not token:
    continue
  try:
    ALLOWED_NETWORKS.append(ipaddress.ip_network(token, strict=False))
  except ValueError:
    pass

def _is_placeholder_url(url):
  if not url:
    return True
  return ("example-icecast.local" in url) or ("your.stream/url" in url)


DEFAULT_P1_INPUT = "radio1_url" if not _is_placeholder_url(RADIO1_URL) else "ompx_prg1in_cap"
DEFAULT_P2_INPUT = "radio2_url" if not _is_placeholder_url(RADIO2_URL) else "ompx_prg2in_cap"


DEFAULT_STATE = {
  "active_program": 1,
  "active_tab": "program1",
  "tab_name_prog1": "Program 1",
  "tab_name_prog2": "Program 2",
  "input_device": DEFAULT_P1_INPUT,
  "input_device_prog1": DEFAULT_P1_INPUT,
  "input_device_prog2": DEFAULT_P2_INPUT,
  "preview_mode": "auto",
  "sample_rate": 48000,
  "wave_window_sec": 3,
  "processing_bypass": False,
  "enable_momentary_ab": False,
  "bypass_level_match_enabled": False,
  "bypass_level_match_db": 0.0,
  "peak_hold_enabled": True,
  "peak_hold_decay": 0.94,
  "processor_input_gain_db": 0.0,
  "pre_gain_db": 0.0,
  "post_gain_db": 0.0,
  "stereo_width": 1.0,
  "hf_tame_db": 0.0,
  "hf_tame_freq": 7000,
  "output_limit": 0.96,
  "band1_drive_db": 0.0,
  "band1_enabled": True,
  "band1_ratio": 2.0,
  "band1_attack_ms": 10.0,
  "band1_release_ms": 120.0,
  "band1_mix": 1.0,
  "band1_drive_db_l": 0.0,
  "band1_drive_db_r": 0.0,
  "band1_mix_l": 1.0,
  "band1_mix_r": 1.0,
  "band2_drive_db": 0.0,
  "band2_enabled": True,
  "band2_ratio": 2.0,
  "band2_attack_ms": 10.0,
  "band2_release_ms": 120.0,
  "band2_mix": 1.0,
  "band2_drive_db_l": 0.0,
  "band2_drive_db_r": 0.0,
  "band2_mix_l": 1.0,
  "band2_mix_r": 1.0,
  "band3_drive_db": 0.0,
  "band3_enabled": True,
  "band3_ratio": 2.0,
  "band3_attack_ms": 10.0,
  "band3_release_ms": 120.0,
  "band3_mix": 1.0,
  "band3_drive_db_l": 0.0,
  "band3_drive_db_r": 0.0,
  "band3_mix_l": 1.0,
  "band3_mix_r": 1.0,
  "band4_drive_db": 0.0,
  "band4_enabled": True,
  "band4_ratio": 2.0,
  "band4_attack_ms": 10.0,
  "band4_release_ms": 120.0,
  "band4_mix": 1.0,
  "band4_drive_db_l": 0.0,
  "band4_drive_db_r": 0.0,
  "band4_mix_l": 1.0,
  "band4_mix_r": 1.0,
  "band5_drive_db": 0.0,
  "band5_enabled": True,
  "band5_ratio": 2.0,
  "band5_attack_ms": 10.0,
  "band5_release_ms": 120.0,
  "band5_mix": 1.0,
  "band5_drive_db_l": 0.0,
  "band5_drive_db_r": 0.0,
  "band5_mix_l": 1.0,
  "band5_mix_r": 1.0,
  "multiband_stereo_independent": False,
  "azimuth_correction_enabled": False,
  "azimuth_delay_ms": 0.0,
  "auto_balance_enabled": False,
  "auto_balance_strength": 0.2,
  "fft_input_device": "ompx_prg1mpx_cap",
  "fft_input_device_prog1": "ompx_prg1mpx_cap",
  "fft_input_device_prog2": "ompx_prg2mpx_cap",
  "fft_sample_rate": 192000,
  "fft_max_hz": 60000,
  "ui_theme": "forest",
  "ui_custom_css": "",
  "patch_mode": "browser",
  "patch_output_device": "default",
}

STATE_LOCK = threading.Lock()
PATCH_LOCK = threading.Lock()
PATCH_PROC = None


def load_state():
  if os.path.exists(STATE_PATH):
    try:
      with open(STATE_PATH, "r", encoding="utf-8") as f:
        loaded = json.load(f)
      merged = dict(DEFAULT_STATE)
      merged.update(loaded)
      return merged
    except Exception:
      return dict(DEFAULT_STATE)
  return dict(DEFAULT_STATE)


def save_state(state):
  os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
  with open(STATE_PATH, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2)


def _parse_bool(value, default=False):
  if isinstance(value, bool):
    return value
  if isinstance(value, str):
    v = value.strip().lower()
    if v in ("1", "true", "yes", "on", "y"):
      return True
    if v in ("0", "false", "no", "off", "n"):
      return False
  return default


def _safe_int(value, default, min_value=0, max_value=31):
  try:
    iv = int(value)
  except Exception:
    return default
  return max(min_value, min(max_value, iv))


def _normalize_pi(value, default):
  s = str(value or "").strip().upper()
  if len(s) == 4 and all(c in "0123456789ABCDEF" for c in s):
    return s
  return default


def _load_json(path):
  if not os.path.exists(path):
    return {}
  try:
    with open(path, "r", encoding="utf-8") as f:
      return json.load(f)
  except Exception:
    return {}


def _write_json(path, payload):
  os.makedirs(os.path.dirname(path), exist_ok=True)
  tmp = f"{path}.tmp"
  with open(tmp, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
  os.replace(tmp, path)


def _read_first_line(path):
  if not os.path.exists(path):
    return ""
  try:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
      return f.readline().strip()
  except Exception:
    return ""


def load_rds_state():
  p1_override = _load_json(RDS_PROG1_OVERRIDE_PATH)
  p2_override = _load_json(RDS_PROG2_OVERRIDE_PATH)
  p1_info = _load_json(RDS_PROG1_INFO_PATH)
  p2_info = _load_json(RDS_PROG2_INFO_PATH)
  return {
    "rds_prog1_ps": str(p1_override.get("ps", ENV.get("RDS_PROG1_PS", p1_info.get("ps", "OMPXFM1"))))[:8],
    "rds_prog1_pi": _normalize_pi(p1_override.get("pi", ENV.get("RDS_PROG1_PI", p1_info.get("pi", "1A01"))), "1A01"),
    "rds_prog1_pty": _safe_int(p1_override.get("pty", ENV.get("RDS_PROG1_PTY", p1_info.get("pty", 10))), 10),
    "rds_prog1_tp": _parse_bool(p1_override.get("tp", ENV.get("RDS_PROG1_TP", p1_info.get("tp", True))), True),
    "rds_prog1_ta": _parse_bool(p1_override.get("ta", ENV.get("RDS_PROG1_TA", p1_info.get("ta", False))), False),
    "rds_prog1_ms": _parse_bool(p1_override.get("ms", ENV.get("RDS_PROG1_MS", p1_info.get("ms", True))), True),
    "rds_prog1_ct_enable": _parse_bool(p1_override.get("ct_enable", ENV.get("RDS_PROG1_CT_ENABLE", True)), True),
    "rds_prog1_ct_mode": str(p1_override.get("ct_mode", ENV.get("RDS_PROG1_CT_MODE", "local"))).lower() if str(p1_override.get("ct_mode", ENV.get("RDS_PROG1_CT_MODE", "local"))).lower() in ("local", "utc") else "local",
    "rds_prog1_rt": str(p1_override.get("rt", _read_first_line(RDS_PROG1_RT_PATH) or p1_info.get("rt", ""))),
    "rds_prog1_ct_current": str(p1_info.get("ct", "")),
    "rds_prog1_updated_at": str(p1_info.get("updated_at", "")),
    "rds_prog2_ps": str(p2_override.get("ps", ENV.get("RDS_PROG2_PS", p2_info.get("ps", "OMPXFM2"))))[:8],
    "rds_prog2_pi": _normalize_pi(p2_override.get("pi", ENV.get("RDS_PROG2_PI", p2_info.get("pi", "1A02"))), "1A02"),
    "rds_prog2_pty": _safe_int(p2_override.get("pty", ENV.get("RDS_PROG2_PTY", p2_info.get("pty", 10))), 10),
    "rds_prog2_tp": _parse_bool(p2_override.get("tp", ENV.get("RDS_PROG2_TP", p2_info.get("tp", True))), True),
    "rds_prog2_ta": _parse_bool(p2_override.get("ta", ENV.get("RDS_PROG2_TA", p2_info.get("ta", False))), False),
    "rds_prog2_ms": _parse_bool(p2_override.get("ms", ENV.get("RDS_PROG2_MS", p2_info.get("ms", True))), True),
    "rds_prog2_ct_enable": _parse_bool(p2_override.get("ct_enable", ENV.get("RDS_PROG2_CT_ENABLE", True)), True),
    "rds_prog2_ct_mode": str(p2_override.get("ct_mode", ENV.get("RDS_PROG2_CT_MODE", "local"))).lower() if str(p2_override.get("ct_mode", ENV.get("RDS_PROG2_CT_MODE", "local"))).lower() in ("local", "utc") else "local",
    "rds_prog2_rt": str(p2_override.get("rt", _read_first_line(RDS_PROG2_RT_PATH) or p2_info.get("rt", ""))),
    "rds_prog2_ct_current": str(p2_info.get("ct", "")),
    "rds_prog2_updated_at": str(p2_info.get("updated_at", "")),
  }


def save_rds_state(payload):
  current = load_rds_state()
  merged = dict(current)
  for key in merged:
    if key in payload:
      merged[key] = payload[key]

  p1 = {
    "ps": str(merged.get("rds_prog1_ps", "OMPXFM1"))[:8],
    "pi": _normalize_pi(merged.get("rds_prog1_pi", "1A01"), "1A01"),
    "pty": _safe_int(merged.get("rds_prog1_pty", 10), 10),
    "tp": _parse_bool(merged.get("rds_prog1_tp", True), True),
    "ta": _parse_bool(merged.get("rds_prog1_ta", False), False),
    "ms": _parse_bool(merged.get("rds_prog1_ms", True), True),
    "ct_enable": _parse_bool(merged.get("rds_prog1_ct_enable", True), True),
    "ct_mode": "utc" if str(merged.get("rds_prog1_ct_mode", "local")).lower() == "utc" else "local",
    "rt": str(merged.get("rds_prog1_rt", "")),
  }
  p2 = {
    "ps": str(merged.get("rds_prog2_ps", "OMPXFM2"))[:8],
    "pi": _normalize_pi(merged.get("rds_prog2_pi", "1A02"), "1A02"),
    "pty": _safe_int(merged.get("rds_prog2_pty", 10), 10),
    "tp": _parse_bool(merged.get("rds_prog2_tp", True), True),
    "ta": _parse_bool(merged.get("rds_prog2_ta", False), False),
    "ms": _parse_bool(merged.get("rds_prog2_ms", True), True),
    "ct_enable": _parse_bool(merged.get("rds_prog2_ct_enable", True), True),
    "ct_mode": "utc" if str(merged.get("rds_prog2_ct_mode", "local")).lower() == "utc" else "local",
    "rt": str(merged.get("rds_prog2_rt", "")),
  }

  _write_json(RDS_PROG1_OVERRIDE_PATH, p1)
  _write_json(RDS_PROG2_OVERRIDE_PATH, p2)

  os.makedirs(os.path.dirname(RDS_PROG1_RT_PATH), exist_ok=True)
  os.makedirs(os.path.dirname(RDS_PROG2_RT_PATH), exist_ok=True)
  with open(RDS_PROG1_RT_PATH, "w", encoding="utf-8") as f:
    f.write((p1["rt"] or "") + "\n")
  with open(RDS_PROG2_RT_PATH, "w", encoding="utf-8") as f:
    f.write((p2["rt"] or "") + "\n")

  return load_rds_state()


def client_allowed(ip):
  if not ALLOWED_NETWORKS:
    return True
  try:
    addr = ipaddress.ip_address(ip)
  except ValueError:
    return False
  for network in ALLOWED_NETWORKS:
    if addr in network:
      return True
  return False


def is_authorized(headers):
  if not AUTH_ENABLE:
    return True
  auth = headers.get("Authorization", "")
  if not auth.startswith("Basic "):
    return False
  try:
    decoded = base64.b64decode(auth.split(" ", 1)[1]).decode("utf-8")
  except Exception:
    return False
  if ":" not in decoded:
    return False
  user, password = decoded.split(":", 1)
  return user == AUTH_USER and password == AUTH_PASSWORD


def _safe_float(value, default, min_value=None, max_value=None):
  try:
    fv = float(value)
  except Exception:
    fv = float(default)
  if min_value is not None:
    fv = max(min_value, fv)
  if max_value is not None:
    fv = min(max_value, fv)
  return fv


def build_preview_filter(state):
  processor_in = _safe_float(state.get("processor_input_gain_db", 0.0), 0.0, -24.0, 24.0)
  pre = float(state.get("pre_gain_db", 0.0))
  post = float(state.get("post_gain_db", 0.0))
  width = _safe_float(state.get("stereo_width", 1.0), 1.0, 0.0, 2.0)
  stereo_independent = _parse_bool(state.get("multiband_stereo_independent", False), False)
  azimuth_enabled = _parse_bool(state.get("azimuth_correction_enabled", False), False)
  azimuth_delay_ms = _safe_float(state.get("azimuth_delay_ms", 0.0), 0.0, -5.0, 5.0)
  auto_balance_enabled = _parse_bool(state.get("auto_balance_enabled", False), False)
  auto_balance_strength = _safe_float(state.get("auto_balance_strength", 0.2), 0.2, 0.0, 1.0)
  hf_tame_db = _safe_float(state.get("hf_tame_db", 0.0), 0.0, -18.0, 18.0)
  hf_tame_freq = int(_safe_float(state.get("hf_tame_freq", 7000), 7000, 1000, 18000))
  limit = _safe_float(state.get("output_limit", 0.96), 0.96, 0.1, 1.0)

  drives = [
    _safe_float(state.get("band1_drive_db", 0.0), 0.0, -18.0, 18.0),
    _safe_float(state.get("band2_drive_db", 0.0), 0.0, -18.0, 18.0),
    _safe_float(state.get("band3_drive_db", 0.0), 0.0, -18.0, 18.0),
    _safe_float(state.get("band4_drive_db", 0.0), 0.0, -18.0, 18.0),
    _safe_float(state.get("band5_drive_db", 0.0), 0.0, -18.0, 18.0),
  ]
  ratios = [
    _safe_float(state.get("band1_ratio", 2.0), 2.0, 1.0, 20.0),
    _safe_float(state.get("band2_ratio", 2.0), 2.0, 1.0, 20.0),
    _safe_float(state.get("band3_ratio", 2.0), 2.0, 1.0, 20.0),
    _safe_float(state.get("band4_ratio", 2.0), 2.0, 1.0, 20.0),
    _safe_float(state.get("band5_ratio", 2.0), 2.0, 1.0, 20.0),
  ]
  attacks = [
    _safe_float(state.get("band1_attack_ms", 10.0), 10.0, 0.1, 200.0),
    _safe_float(state.get("band2_attack_ms", 10.0), 10.0, 0.1, 200.0),
    _safe_float(state.get("band3_attack_ms", 10.0), 10.0, 0.1, 200.0),
    _safe_float(state.get("band4_attack_ms", 10.0), 10.0, 0.1, 200.0),
    _safe_float(state.get("band5_attack_ms", 10.0), 10.0, 0.1, 200.0),
  ]
  releases = [
    _safe_float(state.get("band1_release_ms", 120.0), 120.0, 5.0, 1500.0),
    _safe_float(state.get("band2_release_ms", 120.0), 120.0, 5.0, 1500.0),
    _safe_float(state.get("band3_release_ms", 120.0), 120.0, 5.0, 1500.0),
    _safe_float(state.get("band4_release_ms", 120.0), 120.0, 5.0, 1500.0),
    _safe_float(state.get("band5_release_ms", 120.0), 120.0, 5.0, 1500.0),
  ]
  mixes = [
    _safe_float(state.get("band1_mix", 1.0), 1.0, 0.0, 2.0),
    _safe_float(state.get("band2_mix", 1.0), 1.0, 0.0, 2.0),
    _safe_float(state.get("band3_mix", 1.0), 1.0, 0.0, 2.0),
    _safe_float(state.get("band4_mix", 1.0), 1.0, 0.0, 2.0),
    _safe_float(state.get("band5_mix", 1.0), 1.0, 0.0, 2.0),
  ]
  enabled = [
    _parse_bool(state.get("band1_enabled", True), True),
    _parse_bool(state.get("band2_enabled", True), True),
    _parse_bool(state.get("band3_enabled", True), True),
    _parse_bool(state.get("band4_enabled", True), True),
    _parse_bool(state.get("band5_enabled", True), True),
  ]

  weighted = [max(0.001, m) if en else 0.0 for m, en in zip(mixes, enabled)]
  total_weight = sum(weighted)
  if total_weight <= 0.0:
    weighted = [1.0, 1.0, 1.0, 1.0, 1.0]
    total_weight = 5.0
  avg_ratio = sum(r * w for r, w in zip(ratios, weighted)) / total_weight
  avg_attack = sum(a * w for a, w in zip(attacks, weighted)) / total_weight
  avg_release = sum(r * w for r, w in zip(releases, weighted)) / total_weight

  # Band drive+mix are approximated as per-band EQ emphasis before compression.
  def _compute_band_gains(drive_values, mix_values):
    out = []
    for d, m, en in zip(drive_values, mix_values, enabled):
      if not en:
        out.append(0.0)
      else:
        out.append(d + ((m - 1.0) * 6.0))
    return out

  band_gains = _compute_band_gains(drives, mixes)
  drives_l = [
    _safe_float(state.get("band1_drive_db_l", drives[0]), drives[0], -18.0, 18.0),
    _safe_float(state.get("band2_drive_db_l", drives[1]), drives[1], -18.0, 18.0),
    _safe_float(state.get("band3_drive_db_l", drives[2]), drives[2], -18.0, 18.0),
    _safe_float(state.get("band4_drive_db_l", drives[3]), drives[3], -18.0, 18.0),
    _safe_float(state.get("band5_drive_db_l", drives[4]), drives[4], -18.0, 18.0),
  ]
  drives_r = [
    _safe_float(state.get("band1_drive_db_r", drives[0]), drives[0], -18.0, 18.0),
    _safe_float(state.get("band2_drive_db_r", drives[1]), drives[1], -18.0, 18.0),
    _safe_float(state.get("band3_drive_db_r", drives[2]), drives[2], -18.0, 18.0),
    _safe_float(state.get("band4_drive_db_r", drives[3]), drives[3], -18.0, 18.0),
    _safe_float(state.get("band5_drive_db_r", drives[4]), drives[4], -18.0, 18.0),
  ]
  mixes_l = [
    _safe_float(state.get("band1_mix_l", mixes[0]), mixes[0], 0.0, 2.0),
    _safe_float(state.get("band2_mix_l", mixes[1]), mixes[1], 0.0, 2.0),
    _safe_float(state.get("band3_mix_l", mixes[2]), mixes[2], 0.0, 2.0),
    _safe_float(state.get("band4_mix_l", mixes[3]), mixes[3], 0.0, 2.0),
    _safe_float(state.get("band5_mix_l", mixes[4]), mixes[4], 0.0, 2.0),
  ]
  mixes_r = [
    _safe_float(state.get("band1_mix_r", mixes[0]), mixes[0], 0.0, 2.0),
    _safe_float(state.get("band2_mix_r", mixes[1]), mixes[1], 0.0, 2.0),
    _safe_float(state.get("band3_mix_r", mixes[2]), mixes[2], 0.0, 2.0),
    _safe_float(state.get("band4_mix_r", mixes[3]), mixes[3], 0.0, 2.0),
    _safe_float(state.get("band5_mix_r", mixes[4]), mixes[4], 0.0, 2.0),
  ]
  band_gains_l = _compute_band_gains(drives_l, mixes_l)
  band_gains_r = _compute_band_gains(drives_r, mixes_r)

  if _parse_bool(state.get("processing_bypass", False), False):
    bypass_trim = _safe_float(state.get("bypass_level_match_db", 0.0), 0.0, -24.0, 24.0)
    if _parse_bool(state.get("bypass_level_match_enabled", False), False):
      enabled_band_gains = [g for g, en in zip(band_gains, enabled) if en]
      band_avg = (sum(enabled_band_gains) / len(enabled_band_gains)) if enabled_band_gains else 0.0
      ratio_push = max(0.0, avg_ratio - 1.0)
      estimated = (processor_in + pre + post) + (band_avg * 0.55) + (ratio_push * 0.8)
      bypass_trim += estimated
    bypass_trim = max(-24.0, min(24.0, bypass_trim))
    if abs(bypass_trim) < 0.01:
      return "anull"
    return f"aformat=sample_fmts=fltp,volume={bypass_trim}dB"

  hf_tame_filter = "anull"
  if hf_tame_db != 0.0:
    hf_tame_filter = f"highshelf=f={hf_tame_freq}:g={hf_tame_db}"
  core = (
    f"aformat=sample_fmts=fltp,"
    f"volume={processor_in}dB,"
  )
  if stereo_independent:
    core += (
      f"equalizer=f=80:t=o:w=1.8:g={band_gains_l[0]}:c=FL,"
      f"equalizer=f=80:t=o:w=1.8:g={band_gains_r[0]}:c=FR,"
      f"equalizer=f=250:t=o:w=1.6:g={band_gains_l[1]}:c=FL,"
      f"equalizer=f=250:t=o:w=1.6:g={band_gains_r[1]}:c=FR,"
      f"equalizer=f=1000:t=o:w=1.4:g={band_gains_l[2]}:c=FL,"
      f"equalizer=f=1000:t=o:w=1.4:g={band_gains_r[2]}:c=FR,"
      f"equalizer=f=3500:t=o:w=1.2:g={band_gains_l[3]}:c=FL,"
      f"equalizer=f=3500:t=o:w=1.2:g={band_gains_r[3]}:c=FR,"
      f"equalizer=f=11000:t=o:w=1.1:g={band_gains_l[4]}:c=FL,"
      f"equalizer=f=11000:t=o:w=1.1:g={band_gains_r[4]}:c=FR,"
    )
  else:
    core += (
      f"equalizer=f=80:t=o:w=1.8:g={band_gains[0]},"
      f"equalizer=f=250:t=o:w=1.6:g={band_gains[1]},"
      f"equalizer=f=1000:t=o:w=1.4:g={band_gains[2]},"
      f"equalizer=f=3500:t=o:w=1.2:g={band_gains[3]},"
      f"equalizer=f=11000:t=o:w=1.1:g={band_gains[4]},"
    )
  core += (
    f"acompressor=threshold=0.125:ratio={avg_ratio}:attack={avg_attack}:release={avg_release}:makeup=1,"
    f"volume={pre}dB,"
    f"{hf_tame_filter},"
    f"alimiter=limit={limit},"
  )
  if azimuth_enabled and abs(azimuth_delay_ms) >= 0.01:
    if azimuth_delay_ms > 0:
      core += f"adelay=0|{azimuth_delay_ms},"
    else:
      core += f"adelay={abs(azimuth_delay_ms)}|0,"
  if auto_balance_enabled and auto_balance_strength > 0.0:
    cross = max(0.0, min(1.0, auto_balance_strength))
    keep = 1.0 - (cross * 0.5)
    side = cross * 0.5
    core += f"pan=stereo|c0={keep}*c0+{side}*c1|c1={side}*c0+{keep}*c1,"
  core += (
    f"extrastereo=m={width},"
    f"volume={post}dB"
  )
  return core


def resolve_input_source(input_device):
  dev = str(input_device or "").strip()
  if dev == "radio1_url":
    return str(RADIO1_URL or "").strip(), True
  if dev == "radio2_url":
    return str(RADIO2_URL or "").strip(), True
  return dev, False


def spawn_patch_playback(state):
  global PATCH_PROC
  input_device = str(state.get("input_device", "ompx_prg1in_cap"))
  resolved_input, input_is_url = resolve_input_source(input_device)
  if not resolved_input:
    return
  output_device = str(state.get("patch_output_device", "default"))
  sample_rate = int(float(state.get("sample_rate", 48000)))
  filt = build_preview_filter(state)
  cmd = [
    "ffmpeg",
    "-hide_banner",
    "-loglevel",
    "warning",
    "-nostdin",
  ]
  if input_is_url:
    cmd += [
      "-thread_queue_size",
      "10240",
      "-i",
      resolved_input,
      "-filter:a",
      filt,
      "-ar",
      str(sample_rate),
      "-ac",
      "2",
      "-f",
      "alsa",
      output_device,
    ]
  else:
    cmd += [
      "-f",
      "alsa",
      "-ac",
      "2",
      "-ar",
      str(sample_rate),
      "-i",
      resolved_input,
      "-filter:a",
      filt,
      "-f",
      "alsa",
      output_device,
    ]
  PATCH_PROC = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def stop_patch_playback():
  global PATCH_PROC
  if PATCH_PROC is None:
    return
  try:
    PATCH_PROC.terminate()
    PATCH_PROC.wait(timeout=2)
  except Exception:
    try:
      PATCH_PROC.kill()
    except Exception:
      pass
  PATCH_PROC = None


class Handler(BaseHTTPRequestHandler):
  server_version = "oMPXWebUI/1.0"

  def _send_json(self, obj, status=HTTPStatus.OK):
    payload = json.dumps(obj).encode("utf-8")
    self.send_response(status)
    self.send_header("Content-Type", "application/json")
    self.send_header("Cache-Control", "no-store")
    self.send_header("Content-Length", str(len(payload)))
    self.end_headers()
    self.wfile.write(payload)

  def _deny_if_needed(self):
    client_ip = self.client_address[0]
    if not client_allowed(client_ip):
      self.send_error(HTTPStatus.FORBIDDEN, "Client IP is not allowed")
      return True
    if not is_authorized(self.headers):
      self.send_response(HTTPStatus.UNAUTHORIZED)
      self.send_header("WWW-Authenticate", 'Basic realm="oMPX UI"')
      self.end_headers()
      return True
    return False

  def do_GET(self):
    if self._deny_if_needed():
      return
    parsed = urllib.parse.urlparse(self.path)
    if parsed.path == "/":
      html = PAGE_HTML.encode("utf-8")
      self.send_response(HTTPStatus.OK)
      self.send_header("Content-Type", "text/html; charset=utf-8")
      self.send_header("Content-Length", str(len(html)))
      self.end_headers()
      self.wfile.write(html)
      return
    if parsed.path == "/api/state":
      with STATE_LOCK:
        self._send_json(load_state())
      return
    if parsed.path == "/api/rds_state":
      self._send_json(load_rds_state())
      return
    if parsed.path == "/api/preview.mp3":
      with STATE_LOCK:
        state = load_state()
      qs = urllib.parse.parse_qs(parsed.query or "")
      req_program = str((qs.get("program") or [""])[0]).strip()
      if req_program in ("1", "2"):
        input_device = str(state.get(f"input_device_prog{req_program}", state.get("input_device", "ompx_prg1in_cap")))
      else:
        input_device = str(state.get("input_device", "ompx_prg1in_cap"))
      resolved_input, input_is_url = resolve_input_source(input_device)
      if not resolved_input:
        self.send_error(HTTPStatus.BAD_REQUEST, "Preview source is not configured")
        return
      preview_mode = str(state.get("preview_mode", "auto"))
      sample_rate = int(float(state.get("sample_rate", 48000)))
      filt = build_preview_filter(state)
      is_mpx_input = (not input_is_url) and ("mpx" in resolved_input)
      decode_mpx = (preview_mode == "mpx-decode") or (preview_mode == "auto" and is_mpx_input)
      if input_is_url and decode_mpx:
        decode_mpx = False
      if decode_mpx:
        mpx_decode_graph = (
          "[0:a]pan=mono|c0=c0[m];"
          "[m]lowpass=f=15000[lpr];"
          "[m]bandpass=f=19000:w=1200[p];"
          "[p][p]amultiply,highpass=f=30000,lowpass=f=42000,volume=35[car];"
          "[m]highpass=f=23000,lowpass=f=53000[dsb];"
          "[dsb][car]amultiply,lowpass=f=15000,volume=8[lmr];"
          "[lpr][lmr]amix=inputs=2:weights='1 1'[left];"
          "[lpr][lmr]amix=inputs=2:weights='1 -1'[right];"
          "[left][right]join=inputs=2:channel_layout=stereo,"
          f"{filt}[out]"
        )
        cmd = [
          "ffmpeg",
          "-hide_banner",
          "-loglevel",
          "warning",
          "-nostdin",
          "-f",
          "alsa",
          "-ac",
          "2",
          "-ar",
          "192000",
          "-i",
          resolved_input,
          "-filter_complex",
          mpx_decode_graph,
          "-map",
          "[out]",
          "-ar",
          str(sample_rate),
          "-ac",
          "2",
          "-c:a",
          "libmp3lame",
          "-b:a",
          "192k",
          "-f",
          "mp3",
          "-",
        ]
      else:
        cmd = [
          "ffmpeg",
          "-hide_banner",
          "-loglevel",
          "warning",
          "-nostdin",
        ]
        if input_is_url:
          cmd += [
            "-thread_queue_size",
            "10240",
            "-i",
            resolved_input,
            "-filter:a",
            filt,
            "-ar",
            str(sample_rate),
            "-ac",
            "2",
            "-c:a",
            "libmp3lame",
            "-b:a",
            "192k",
            "-f",
            "mp3",
            "-",
          ]
        else:
          cmd += [
            "-f",
            "alsa",
            "-ac",
            "2",
            "-ar",
            str(sample_rate),
            "-i",
            resolved_input,
            "-filter:a",
            filt,
            "-c:a",
            "libmp3lame",
            "-b:a",
            "192k",
            "-f",
            "mp3",
            "-",
          ]
      proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
      self.send_response(HTTPStatus.OK)
      self.send_header("Content-Type", "audio/mpeg")
      self.send_header("Cache-Control", "no-cache")
      self.end_headers()
      try:
        while True:
          chunk = proc.stdout.read(8192)
          if not chunk:
            break
          self.wfile.write(chunk)
      except (BrokenPipeError, ConnectionResetError):
        pass
      finally:
        try:
          proc.terminate()
        except Exception:
          pass
      return
    if parsed.path == "/api/preview_input.mp3":
      with STATE_LOCK:
        state = load_state()
      qs = urllib.parse.parse_qs(parsed.query or "")
      req_program = str((qs.get("program") or [""])[0]).strip()
      if req_program in ("1", "2"):
        input_device = str(state.get(f"input_device_prog{req_program}", state.get("input_device", "ompx_prg1in_cap")))
      else:
        input_device = str(state.get("input_device", "ompx_prg1in_cap"))
      resolved_input, input_is_url = resolve_input_source(input_device)
      if not resolved_input:
        self.send_error(HTTPStatus.BAD_REQUEST, "Input source is not configured")
        return
      preview_mode = str(state.get("preview_mode", "auto"))
      sample_rate = int(float(state.get("sample_rate", 48000)))
      filt = "anull"
      is_mpx_input = (not input_is_url) and ("mpx" in resolved_input)
      decode_mpx = (preview_mode == "mpx-decode") or (preview_mode == "auto" and is_mpx_input)
      if input_is_url and decode_mpx:
        decode_mpx = False
      if decode_mpx:
        mpx_decode_graph = (
          "[0:a]pan=mono|c0=c0[m];"
          "[m]lowpass=f=15000[lpr];"
          "[m]bandpass=f=19000:w=1200[p];"
          "[p][p]amultiply,highpass=f=30000,lowpass=f=42000,volume=35[car];"
          "[m]highpass=f=23000,lowpass=f=53000[dsb];"
          "[dsb][car]amultiply,lowpass=f=15000,volume=8[lmr];"
          "[lpr][lmr]amix=inputs=2:weights='1 1'[left];"
          "[lpr][lmr]amix=inputs=2:weights='1 -1'[right];"
          "[left][right]join=inputs=2:channel_layout=stereo,"
          f"{filt}[out]"
        )
        cmd = [
          "ffmpeg",
          "-hide_banner",
          "-loglevel",
          "warning",
          "-nostdin",
          "-f",
          "alsa",
          "-ac",
          "2",
          "-ar",
          "192000",
          "-i",
          resolved_input,
          "-filter_complex",
          mpx_decode_graph,
          "-map",
          "[out]",
          "-ar",
          str(sample_rate),
          "-ac",
          "2",
          "-c:a",
          "libmp3lame",
          "-b:a",
          "192k",
          "-f",
          "mp3",
          "-",
        ]
      else:
        cmd = [
          "ffmpeg",
          "-hide_banner",
          "-loglevel",
          "warning",
          "-nostdin",
        ]
        if input_is_url:
          cmd += [
            "-thread_queue_size",
            "10240",
            "-i",
            resolved_input,
            "-filter:a",
            filt,
            "-ar",
            str(sample_rate),
            "-ac",
            "2",
            "-c:a",
            "libmp3lame",
            "-b:a",
            "192k",
            "-f",
            "mp3",
            "-",
          ]
        else:
          cmd += [
            "-f",
            "alsa",
            "-ac",
            "2",
            "-ar",
            str(sample_rate),
            "-i",
            resolved_input,
            "-filter:a",
            filt,
            "-c:a",
            "libmp3lame",
            "-b:a",
            "192k",
            "-f",
            "mp3",
            "-",
          ]
      proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
      self.send_response(HTTPStatus.OK)
      self.send_header("Content-Type", "audio/mpeg")
      self.send_header("Cache-Control", "no-cache")
      self.end_headers()
      try:
        while True:
          chunk = proc.stdout.read(8192)
          if not chunk:
            break
          self.wfile.write(chunk)
      except (BrokenPipeError, ConnectionResetError):
        pass
      finally:
        try:
          proc.terminate()
        except Exception:
          pass
      return
    if parsed.path == "/api/mpx_fft.png":
      with STATE_LOCK:
        state = load_state()
      qs = urllib.parse.parse_qs(parsed.query or "")
      req_program = str((qs.get("program") or [""])[0]).strip()
      if req_program in ("1", "2"):
        fft_input_device = str(state.get(f"fft_input_device_prog{req_program}", state.get("fft_input_device", "ompx_prg1mpx_cap")))
      else:
        fft_input_device = str(state.get("fft_input_device", "ompx_prg1mpx_cap"))
      resolved_fft_input, fft_input_is_url = resolve_input_source(fft_input_device)
      if not resolved_fft_input:
        self.send_error(HTTPStatus.BAD_REQUEST, "FFT source is not configured")
        return
      fft_sample_rate = int(float(state.get("fft_sample_rate", 192000)))
      fft_max_hz = int(float(state.get("fft_max_hz", 60000)))
      if fft_sample_rate < 32000:
        fft_sample_rate = 192000
      nyquist = int(fft_sample_rate / 2)
      if fft_max_hz < 1000 or fft_max_hz > nyquist:
        fft_max_hz = min(60000, nyquist)
      stop_hz = fft_max_hz
      analysis_rate = max(32000, min(384000, stop_hz * 2))
      cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-nostdin",
      ]
      if fft_input_is_url:
        cmd += [
          "-thread_queue_size",
          "10240",
          "-i",
          resolved_fft_input,
        ]
      else:
        cmd += [
          "-f",
          "alsa",
          "-ac",
          "2",
          "-ar",
          str(fft_sample_rate),
          "-i",
          resolved_fft_input,
        ]
      cmd += [
        "-t",
        "0.8",
        "-filter_complex",
        (
          f"[0:a]pan=mono|c0=c0,"
          f"aresample={analysis_rate},"
          "highpass=f=50,"
          "showfreqs=s=1280x360:mode=bar:fscale=lin:ascale=sqrt:cmode=combined:win_size=65536"
        ),
        "-frames:v",
        "1",
        "-f",
        "image2pipe",
        "-vcodec",
        "png",
        "-",
      ]
      proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      try:
        out, err = proc.communicate(timeout=3)
      except subprocess.TimeoutExpired:
        try:
          proc.kill()
        except Exception:
          pass
        self.send_error(HTTPStatus.GATEWAY_TIMEOUT, "FFT render timed out")
        return
      if proc.returncode != 0 or not out:
        self.send_error(HTTPStatus.BAD_GATEWAY, f"FFT render failed: {err.decode('utf-8', errors='ignore')[:180]}")
        return
      self.send_response(HTTPStatus.OK)
      self.send_header("Content-Type", "image/png")
      self.send_header("Cache-Control", "no-cache")
      self.send_header("Content-Length", str(len(out)))
      self.end_headers()
      self.wfile.write(out)
      return
    self.send_error(HTTPStatus.NOT_FOUND, "Not found")

  def do_POST(self):
    if self._deny_if_needed():
      return
    length = int(self.headers.get("Content-Length", "0"))
    raw = self.rfile.read(length) if length > 0 else b"{}"
    try:
      payload = json.loads(raw.decode("utf-8"))
    except Exception:
      payload = {}
    if self.path == "/api/state":
      with STATE_LOCK:
        state = load_state()
        for key in DEFAULT_STATE:
          if key in payload:
            state[key] = payload[key]
        save_state(state)
      self._send_json({"ok": True, "state": state})
      return
    if self.path == "/api/rds_state":
      state = save_rds_state(payload)
      self._send_json({"ok": True, "state": state})
      return
    if self.path == "/api/patch/start":
      with STATE_LOCK:
        state = load_state()
      with PATCH_LOCK:
        stop_patch_playback()
        spawn_patch_playback(state)
      self._send_json({"ok": True, "message": "Patch playback started"})
      return
    if self.path == "/api/patch/stop":
      with PATCH_LOCK:
        stop_patch_playback()
      self._send_json({"ok": True, "message": "Patch playback stopped"})
      return
    self.send_error(HTTPStatus.NOT_FOUND, "Not found")


PAGE_HTML = """<!doctype html>
<html>
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>oMPX Live Control</title>
  <style>
  :root { --bg:#0f1b1a; --card:#132825; --accent:#f2b642; --ink:#f4f7f5; --muted:#9fb8b0; }
  body { margin:0; font-family: ui-sans-serif, sans-serif; background: radial-gradient(circle at 10% 10%, #1c3b35, var(--bg)); color:var(--ink); }
  .wrap { max-width:1080px; margin:0 auto; padding:24px; }
  .grid { display:grid; grid-template-columns:1fr 1fr; gap:16px; }
  .card { background:linear-gradient(180deg, #1a322e, var(--card)); border:1px solid #2a4f47; border-radius:12px; padding:14px; }
  h1 { margin:0 0 12px; font-size:28px; letter-spacing:0.03em; }
  label { display:block; font-size:13px; color:var(--muted); margin-top:8px; }
  input, select, button { width:100%; margin-top:4px; padding:8px; border-radius:8px; border:1px solid #365f55; background:#0d1f1c; color:var(--ink); }
  button { cursor:pointer; background:linear-gradient(180deg, #f2b642, #d99424); color:#1b1406; font-weight:600; }
  .row { display:grid; grid-template-columns:1fr 1fr; gap:8px; }
  canvas { width:100%; height:140px; background:#0a1412; border:1px solid #2a4f47; border-radius:8px; }
  .status { font-size:12px; color:var(--muted); margin-top:10px; }
  .meter-grid { display:grid; grid-template-columns:1fr; gap:8px; margin-top:8px; }
  .meter-row { display:grid; grid-template-columns:86px 1fr 62px; gap:8px; align-items:center; }
  .meter-row .name { font-size:12px; color:var(--muted); }
  .meter-row .db { font-size:12px; color:var(--ink); text-align:right; }
  .meter-track { height:10px; border-radius:999px; border:1px solid #2a4f47; background:#0a1412; overflow:hidden; }
  .meter-fill { height:100%; width:0%; background:linear-gradient(90deg, #2fd38a, #f2b642); transition:width 120ms linear; }
  .tabs { display:flex; gap:8px; margin-bottom:10px; align-items:center; }
  .tab-btn { width:auto; padding:8px 12px; border-radius:999px; border:1px solid #365f55; background:#0d1f1c; color:var(--ink); }
  .tab-btn.active { background:linear-gradient(180deg, #f2b642, #d99424); color:#1b1406; border-color:#d99424; }
  .tab-name { max-width:180px; }
  .program-field { display:none; }
  .global-field { display:none; }
  .program-field.active { display:block; }
  .global-field.active { display:block; }
  .stereo-adv { display:none; }
  .stereo-adv.active { display:block; }
  @media (max-width:900px) { .grid { grid-template-columns:1fr; } }
  </style>
  <style id="ui_custom_css_tag"></style>
</head>
<body>
  <div class=\"wrap\">
  <h1>oMPX Live Control + Patch Preview</h1>
  <div class=\"grid\">
    <div class=\"card\"> 
    <div class=\"tabs\">
      <button type=\"button\" id=\"tab_prog1\" class=\"tab-btn active\">Program 1</button>
      <button type=\"button\" id=\"tab_prog2\" class=\"tab-btn\">Program 2</button>
      <button type=\"button\" id=\"tab_global\" class=\"tab-btn\">Global Settings</button>
    </div>
    <div class=\"row\">
      <div><label>Program 1 Tab Name</label><input id=\"tab_name_prog1\" class=\"tab-name\" type=\"text\" maxlength=\"24\" /></div>
      <div><label>Program 2 Tab Name</label><input id=\"tab_name_prog2\" class=\"tab-name\" type=\"text\" maxlength=\"24\" /></div>
    </div>
    <div class=\"global-field\">
      <label style=\"margin-top:8px\">Global Settings</label>
      <label><input id=\"enable_momentary_ab\" type=\"checkbox\" /> Enable Momentary A/B Hold (optional)</label>
      <div class=\"status\">When enabled, hold the A/B button to temporarily bypass processing, then release to return.</div>
    </div>
    <div class=\"row\">
      <div>
      <label>Input Channel</label>
      <select id=\"input_device\">
        <option value=\"radio1_url\">Program 1 stream URL</option>
        <option value=\"radio2_url\">Program 2 stream URL</option>
        <option value=\"ompx_prg1in_cap\">Program 1 input</option>
        <option value=\"ompx_prg2in_cap\">Program 2 input</option>
        <option value=\"ompx_prg1mpx_cap\">Program 1 MPX path</option>
        <option value=\"ompx_prg2mpx_cap\">Program 2 MPX path</option>
      </select>
      </div>
      <div>
      <label>Sample Rate</label>
      <input id=\"sample_rate\" type=\"number\" min=\"8000\" max=\"192000\" step=\"1000\" />
      </div>
    </div>
    <div class=\"row\">
      <div>
      <label>Waveform Window (seconds)</label>
      <input id=\"wave_window_sec\" type=\"range\" min=\"0.25\" max=\"10\" step=\"0.25\" />
      <div class=\"status\" id=\"wave_window_readout\">3.00 s</div>
      </div>
      <div>
      <label>Scope Capture</label>
      <div class=\"row\">
        <div><button id=\"analysis_pause\" type=\"button\">Pause Scope</button></div>
        <div><button id=\"analysis_step\" type=\"button\">Step Frame</button></div>
      </div>
      </div>
    </div>
    <div class=\"row\">
      <div>
      <label>Preview Decode Mode</label>
      <select id=\"preview_mode\">
        <option value=\"auto\">Auto (decode MPX inputs)</option>
        <option value=\"audio\">Audio chain only</option>
        <option value=\"mpx-decode\">Force MPX stereo decode</option>
      </select>
      </div>
      <div></div>
    </div>
    <div class=\"row\">
      <div><label>Pre Gain (dB)</label><input id=\"pre_gain_db\" type=\"number\" step=\"0.1\" /></div>
      <div><label>Post Gain (dB)</label><input id=\"post_gain_db\" type=\"number\" step=\"0.1\" /></div>
    </div>
    <div class=\"row\">
      <div><label>Processor Input Gain (dB)</label><input id=\"processor_input_gain_db\" type=\"number\" step=\"0.1\" min=\"-24\" max=\"24\" /></div>
      <div>
        <label>Peak Hold Overlay</label>
        <div class=\"row\">
          <div><label><input id=\"peak_hold_enabled\" type=\"checkbox\" /> Enable</label></div>
          <div><input id=\"peak_hold_decay\" type=\"number\" step=\"0.01\" min=\"0.50\" max=\"0.999\" /></div>
        </div>
      </div>
    </div>
    <label style=\"margin-top:12px\">5-Band Processor (Drive / Ratio / Attack / Release / Mix)</label>
    <div class=\"row\" style=\"margin-bottom:4px\">
      <div>Band Bypass</div>
      <div style=\"display:grid; grid-template-columns:repeat(5,1fr); gap:6px;\">
        <label><input id=\"band1_enabled\" type=\"checkbox\" checked /> B1</label>
        <label><input id=\"band2_enabled\" type=\"checkbox\" checked /> B2</label>
        <label><input id=\"band3_enabled\" type=\"checkbox\" checked /> B3</label>
        <label><input id=\"band4_enabled\" type=\"checkbox\" checked /> B4</label>
        <label><input id=\"band5_enabled\" type=\"checkbox\" checked /> B5</label>
      </div>
    </div>
    <div class=\"row\"><div>Sub 30-120</div><div style=\"display:grid; grid-template-columns:repeat(5,1fr); gap:6px;\"><input id=\"band1_drive_db\" type=\"number\" step=\"0.1\" placeholder=\"Drive dB\" /><input id=\"band1_ratio\" type=\"number\" step=\"0.1\" placeholder=\"Ratio\" /><input id=\"band1_attack_ms\" type=\"number\" step=\"0.1\" placeholder=\"Attack ms\" /><input id=\"band1_release_ms\" type=\"number\" step=\"1\" placeholder=\"Release ms\" /><input id=\"band1_mix\" type=\"number\" step=\"0.01\" placeholder=\"Mix\" /></div></div>
    <div class=\"row\"><div>Low 120-400</div><div style=\"display:grid; grid-template-columns:repeat(5,1fr); gap:6px;\"><input id=\"band2_drive_db\" type=\"number\" step=\"0.1\" placeholder=\"Drive dB\" /><input id=\"band2_ratio\" type=\"number\" step=\"0.1\" placeholder=\"Ratio\" /><input id=\"band2_attack_ms\" type=\"number\" step=\"0.1\" placeholder=\"Attack ms\" /><input id=\"band2_release_ms\" type=\"number\" step=\"1\" placeholder=\"Release ms\" /><input id=\"band2_mix\" type=\"number\" step=\"0.01\" placeholder=\"Mix\" /></div></div>
    <div class=\"row\"><div>Mid 400-2k</div><div style=\"display:grid; grid-template-columns:repeat(5,1fr); gap:6px;\"><input id=\"band3_drive_db\" type=\"number\" step=\"0.1\" placeholder=\"Drive dB\" /><input id=\"band3_ratio\" type=\"number\" step=\"0.1\" placeholder=\"Ratio\" /><input id=\"band3_attack_ms\" type=\"number\" step=\"0.1\" placeholder=\"Attack ms\" /><input id=\"band3_release_ms\" type=\"number\" step=\"1\" placeholder=\"Release ms\" /><input id=\"band3_mix\" type=\"number\" step=\"0.01\" placeholder=\"Mix\" /></div></div>
    <div class=\"row\"><div>Presence 2k-6k</div><div style=\"display:grid; grid-template-columns:repeat(5,1fr); gap:6px;\"><input id=\"band4_drive_db\" type=\"number\" step=\"0.1\" placeholder=\"Drive dB\" /><input id=\"band4_ratio\" type=\"number\" step=\"0.1\" placeholder=\"Ratio\" /><input id=\"band4_attack_ms\" type=\"number\" step=\"0.1\" placeholder=\"Attack ms\" /><input id=\"band4_release_ms\" type=\"number\" step=\"1\" placeholder=\"Release ms\" /><input id=\"band4_mix\" type=\"number\" step=\"0.01\" placeholder=\"Mix\" /></div></div>
    <div class=\"row\"><div>Air 6k-15k</div><div style=\"display:grid; grid-template-columns:repeat(5,1fr); gap:6px;\"><input id=\"band5_drive_db\" type=\"number\" step=\"0.1\" placeholder=\"Drive dB\" /><input id=\"band5_ratio\" type=\"number\" step=\"0.1\" placeholder=\"Ratio\" /><input id=\"band5_attack_ms\" type=\"number\" step=\"0.1\" placeholder=\"Attack ms\" /><input id=\"band5_release_ms\" type=\"number\" step=\"1\" placeholder=\"Release ms\" /><input id=\"band5_mix\" type=\"number\" step=\"0.01\" placeholder=\"Mix\" /></div></div>
    <div class=\"row\">
      <div><label>Stereo Width</label><input id=\"stereo_width\" type=\"number\" step=\"0.01\" min=\"0\" max=\"2\" /></div>
      <div><label>Limiter Ceiling (0..1)</label><input id=\"output_limit\" type=\"number\" step=\"0.01\" min=\"0.1\" max=\"1\" /></div>
    </div>
    <div class=\"row\">
      <div><label>HF Tame (dB)</label><input id=\"hf_tame_db\" type=\"number\" step=\"0.1\" /></div>
      <div><label>HF Tame Freq (Hz)</label><input id=\"hf_tame_freq\" type=\"number\" step=\"100\" /></div>
    </div>
    <div class=\"row global-field\">
      <div>
      <label>Color Theme</label>
      <select id=\"ui_theme\">
        <option value=\"forest\">Forest (default)</option>
        <option value=\"daylight\">Daylight</option>
        <option value=\"midnight\">Midnight</option>
        <option value=\"amber\">Amber Scope</option>
      </select>
      </div>
      <div>
      <label>&nbsp;</label>
      <button id=\"theme_apply\">Apply Theme</button>
      </div>
    </div>
    <label class=\"global-field\">Custom CSS (optional)</label>
    <textarea class=\"global-field\" id=\"ui_custom_css\" rows=\"4\" style=\"width:100%; margin-top:4px; padding:8px; border-radius:8px; border:1px solid #365f55; background:#0d1f1c; color:var(--ink);\"></textarea>
    <button class=\"global-field\" id=\"css_apply\" style=\"margin-top:8px;\">Apply Custom CSS</button>
    <div class=\"row\" style=\"margin-top:8px\">
      <div><label><input id=\"processing_bypass\" type=\"checkbox\" /> Bypass All Processing</label></div>
      <div><button id=\"processing_bypass_toggle\" type=\"button\">Toggle Processing Bypass</button></div>
    </div>
    <div id=\"momentary_wrap\" style=\"display:none; margin-top:8px\"><button id=\"processing_bypass_hold\" type=\"button\">Hold For Bypass A/B</button></div>
    <div class=\"row\">
      <div><label><input id=\"bypass_level_match_enabled\" type=\"checkbox\" /> Auto Level Match In Bypass (optional)</label></div>
      <div><label>Bypass Level Trim (dB)</label><input id=\"bypass_level_match_db\" type=\"number\" step=\"0.1\" min=\"-24\" max=\"24\" /></div>
    </div>
    <button id=\"apply\">Apply and Refresh Preview</button>
    <div class=\"row\" style=\"margin-top:8px\">
      <div><button id=\"patch_start\">Start Hardware Patch</button></div>
      <div><button id=\"patch_stop\">Stop Hardware Patch</button></div>
    </div>
    <label>Hardware Patch Output Device</label>
    <input id=\"patch_output_device\" type=\"text\" />
    <div class=\"row\">
      <div>
      <label>FFT Input Device (MPX)</label>
      <select id=\"fft_input_device\">
        <option value=\"radio1_url\">Program 1 stream URL</option>
        <option value=\"radio2_url\">Program 2 stream URL</option>
        <option value=\"ompx_prg1mpx_cap\">Program 1 MPX capture</option>
        <option value=\"ompx_prg2mpx_cap\">Program 2 MPX capture</option>
        <option value=\"ompx_prg1in_cap\">Program 1 audio input</option>
        <option value=\"ompx_prg2in_cap\">Program 2 audio input</option>
      </select>
      </div>
      <div>
      <label>FFT Max Hz</label>
      <input id=\"fft_max_hz\" type=\"number\" min=\"1000\" max=\"96000\" step=\"1000\" />
      </div>
    </div>
    <div class=\"row\">
      <div><label>FFT Sample Rate</label><input id=\"fft_sample_rate\" type=\"number\" min=\"32000\" max=\"384000\" step=\"1000\" /></div>
      <div><label>&nbsp;</label><button id=\"fft_refresh\">Refresh FFT Now</button></div>
    </div>
    <label style=\"margin-top:12px\">RDS Live Overrides</label>
    <div class=\"row\">
      <div class=\"program-field program-1\"><label>P1 PS</label><input id=\"rds_prog1_ps\" type=\"text\" maxlength=\"8\" /></div>
      <div class=\"program-field program-2\"><label>P2 PS</label><input id=\"rds_prog2_ps\" type=\"text\" maxlength=\"8\" /></div>
    </div>
    <div class=\"row\">
      <div class=\"program-field program-1\"><label>P1 PI (hex)</label><input id=\"rds_prog1_pi\" type=\"text\" maxlength=\"4\" /></div>
      <div class=\"program-field program-2\"><label>P2 PI (hex)</label><input id=\"rds_prog2_pi\" type=\"text\" maxlength=\"4\" /></div>
    </div>
    <div class=\"row\">
      <div class=\"program-field program-1\"><label>P1 PTY (0-31)</label><input id=\"rds_prog1_pty\" type=\"number\" min=\"0\" max=\"31\" step=\"1\" /></div>
      <div class=\"program-field program-2\"><label>P2 PTY (0-31)</label><input id=\"rds_prog2_pty\" type=\"number\" min=\"0\" max=\"31\" step=\"1\" /></div>
    </div>
    <div class=\"row\">
      <div class=\"program-field program-1\"><label>P1 RT Text</label><input id=\"rds_prog1_rt\" type=\"text\" /></div>
      <div class=\"program-field program-2\"><label>P2 RT Text</label><input id=\"rds_prog2_rt\" type=\"text\" /></div>
    </div>
    <div class=\"row\">
      <div class=\"program-field program-1\">
        <label>P1 CT Mode</label>
        <select id=\"rds_prog1_ct_mode\"><option value=\"local\">Local</option><option value=\"utc\">UTC</option></select>
      </div>
      <div class=\"program-field program-2\">
        <label>P2 CT Mode</label>
        <select id=\"rds_prog2_ct_mode\"><option value=\"local\">Local</option><option value=\"utc\">UTC</option></select>
      </div>
    </div>
    <div class=\"row\">
      <div class=\"program-field program-1\">
        <label>P1 Flags</label>
        <div style=\"display:grid; grid-template-columns:repeat(4,1fr); gap:6px; margin-top:6px;\">
          <label><input id=\"rds_prog1_tp\" type=\"checkbox\" /> TP</label>
          <label><input id=\"rds_prog1_ta\" type=\"checkbox\" /> TA</label>
          <label><input id=\"rds_prog1_ms\" type=\"checkbox\" /> MS</label>
          <label><input id=\"rds_prog1_ct_enable\" type=\"checkbox\" /> CT</label>
        </div>
      </div>
      <div class=\"program-field program-2\">
        <label>P2 Flags</label>
        <div style=\"display:grid; grid-template-columns:repeat(4,1fr); gap:6px; margin-top:6px;\">
          <label><input id=\"rds_prog2_tp\" type=\"checkbox\" /> TP</label>
          <label><input id=\"rds_prog2_ta\" type=\"checkbox\" /> TA</label>
          <label><input id=\"rds_prog2_ms\" type=\"checkbox\" /> MS</label>
          <label><input id=\"rds_prog2_ct_enable\" type=\"checkbox\" /> CT</label>
        </div>
      </div>
    </div>
    <button id=\"rds_apply\" style=\"margin-top:8px;\">Apply RDS Overrides</button>
    <div class=\"row\" style=\"margin-top:8px\">
      <div class=\"status program-field program-1\">P1 CT: <span id=\"rds_prog1_ct_current\">-</span> | Updated: <span id=\"rds_prog1_updated_at\">-</span></div>
      <div class=\"status program-field program-2\">P2 CT: <span id=\"rds_prog2_ct_current\">-</span> | Updated: <span id=\"rds_prog2_updated_at\">-</span></div>
    </div>
    <audio id=\"audio\" controls autoplay style=\"width:100%; margin-top:10px\"></audio>
    <div class=\"status\" id=\"status\">Ready.</div>
    </div>
    <div class=\"card\">
    <label>Waveform</label>
    <canvas id=\"wave\" width=\"900\" height=\"280\"></canvas>
    <label style=\"margin-top:12px\">Band Spectrum</label>
    <canvas id=\"spec\" width=\"900\" height=\"280\"></canvas>
    <label style=\"margin-top:12px\">Processor Band Meters</label>
    <div class=\"meter-grid\" id=\"band_meters\">
      <div class=\"meter-row\"><span class=\"name\">Sub (30-120)</span><div class=\"meter-track\"><div id=\"meter_sub\" class=\"meter-fill\"></div></div><span id=\"meter_sub_db\" class=\"db\">-inf dB</span></div>
      <div class=\"meter-row\"><span class=\"name\">Low (120-400)</span><div class=\"meter-track\"><div id=\"meter_low\" class=\"meter-fill\"></div></div><span id=\"meter_low_db\" class=\"db\">-inf dB</span></div>
      <div class=\"meter-row\"><span class=\"name\">Mid (400-2k)</span><div class=\"meter-track\"><div id=\"meter_mid\" class=\"meter-fill\"></div></div><span id=\"meter_mid_db\" class=\"db\">-inf dB</span></div>
      <div class=\"meter-row\"><span class=\"name\">Presence (2k-6k)</span><div class=\"meter-track\"><div id=\"meter_pres\" class=\"meter-fill\"></div></div><span id=\"meter_pres_db\" class=\"db\">-inf dB</span></div>
      <div class=\"meter-row\"><span class=\"name\">Air (6k-15k)</span><div class=\"meter-track\"><div id=\"meter_air\" class=\"meter-fill\"></div></div><span id=\"meter_air_db\" class=\"db\">-inf dB</span></div>
    </div>
    <label style=\"margin-top:12px\">MPX FFT Snapshot (server-side)</label>
    <div style=\"position:relative; border:1px solid #2a4f47; border-radius:8px; overflow:hidden; background:#0a1412;\">
      <img id=\"fft_img\" alt=\"MPX FFT\" style=\"display:block; width:100%; height:300px; object-fit:fill;\" />
      <div id=\"pilot_marker\" style=\"position:absolute; top:0; bottom:0; width:2px; background:#f2b642; opacity:0.9;\"></div>
      <div id=\"sub_marker\" style=\"position:absolute; top:0; bottom:0; width:2px; background:#52d3c7; opacity:0.9;\"></div>
      <div style=\"position:absolute; top:6px; left:8px; font-size:11px; color:#f2b642; background:#0008; padding:2px 6px; border-radius:4px;\">19 kHz pilot</div>
      <div style=\"position:absolute; top:6px; left:120px; font-size:11px; color:#52d3c7; background:#0008; padding:2px 6px; border-radius:4px;\">38 kHz L-R DSB</div>
    </div>
    </div>
  </div>
  </div>
  <script>
  const ids = ["input_device","preview_mode","sample_rate","wave_window_sec","processor_input_gain_db","bypass_level_match_db","peak_hold_decay","pre_gain_db","post_gain_db","stereo_width","output_limit","hf_tame_db","hf_tame_freq","patch_output_device","fft_input_device","fft_sample_rate","fft_max_hz","ui_theme","ui_custom_css","tab_name_prog1","tab_name_prog2","band1_drive_db","band1_ratio","band1_attack_ms","band1_release_ms","band1_mix","band2_drive_db","band2_ratio","band2_attack_ms","band2_release_ms","band2_mix","band3_drive_db","band3_ratio","band3_attack_ms","band3_release_ms","band3_mix","band4_drive_db","band4_ratio","band4_attack_ms","band4_release_ms","band4_mix","band5_drive_db","band5_ratio","band5_attack_ms","band5_release_ms","band5_mix"];
  const boolStateIds = ["processing_bypass","enable_momentary_ab","bypass_level_match_enabled","peak_hold_enabled","band1_enabled","band2_enabled","band3_enabled","band4_enabled","band5_enabled"];
  const programScopedIds = ["input_device","fft_input_device"];
  const rdsIds = ["rds_prog1_ps","rds_prog1_pi","rds_prog1_pty","rds_prog1_rt","rds_prog1_ct_mode","rds_prog2_ps","rds_prog2_pi","rds_prog2_pty","rds_prog2_rt","rds_prog2_ct_mode"];
  const rdsBoolIds = ["rds_prog1_tp","rds_prog1_ta","rds_prog1_ms","rds_prog1_ct_enable","rds_prog2_tp","rds_prog2_ta","rds_prog2_ms","rds_prog2_ct_enable"];
  const rdsLiveTextIds = ["rds_prog1_ct_current","rds_prog1_updated_at","rds_prog2_ct_current","rds_prog2_updated_at"];
  const st = document.getElementById("status");
  const audio = document.getElementById("audio");
  const fftImg = document.getElementById("fft_img");
  const pilotMarker = document.getElementById("pilot_marker");
  const subMarker = document.getElementById("sub_marker");
  const customCssTag = document.getElementById("ui_custom_css_tag");
  const tabProg1 = document.getElementById("tab_prog1");
  const tabProg2 = document.getElementById("tab_prog2");
  const tabGlobal = document.getElementById("tab_global");
  const waveWindowCtl = document.getElementById("wave_window_sec");
  const waveWindowReadout = document.getElementById("wave_window_readout");
  const processingBypassCtl = document.getElementById("processing_bypass");
  const processingBypassToggleBtn = document.getElementById("processing_bypass_toggle");
  const processingBypassHoldBtn = document.getElementById("processing_bypass_hold");
  const momentaryWrap = document.getElementById("momentary_wrap");
  const enableMomentaryAbCtl = document.getElementById("enable_momentary_ab");
  const analysisPauseBtn = document.getElementById("analysis_pause");
  const analysisStepBtn = document.getElementById("analysis_step");
  let activeProgram = 1;
  let activeTab = 'program1';
  let currentState = {};
  let fftTimer = null;
  let analysisPaused = false;
  let bypassBeforeHold = null;
  const waveHistory = [];
  const WAVE_POINTS_PER_FRAME = 64;
  const WAVE_HISTORY_MAX_SECONDS = 20;
  const peakBars = new Array(64).fill(0);
  let waveFrameCounter = 0;

  const themePalettes = {
    forest: {"--bg":"#0f1b1a","--card":"#132825","--accent":"#f2b642","--ink":"#f4f7f5","--muted":"#9fb8b0"},
    daylight: {"--bg":"#dbe6ef","--card":"#ffffff","--accent":"#1e88e5","--ink":"#142332","--muted":"#5c7286"},
    midnight: {"--bg":"#0a0f1e","--card":"#111a32","--accent":"#56ccf2","--ink":"#ebf2ff","--muted":"#9cb4dc"},
    amber: {"--bg":"#170f05","--card":"#2a1c08","--accent":"#ffb300","--ink":"#fff5dd","--muted":"#d6b97a"},
  };

  function setStatus(msg){ st.textContent = msg; }

  function updateMomentaryControlVisibility(){
    const enabled = !!enableMomentaryAbCtl.checked;
    momentaryWrap.style.display = enabled ? 'block' : 'none';
  }

  function updateWaveWindowReadout(){
    const sec = Number(waveWindowCtl.value || 3);
    waveWindowReadout.textContent = `${sec.toFixed(2)} s`;
  }

  function programKey(base, program){ return `${base}_prog${program}`; }

  function updateTabTitles(){
    const t1 = (document.getElementById('tab_name_prog1').value || 'Program 1').trim();
    const t2 = (document.getElementById('tab_name_prog2').value || 'Program 2').trim();
    tabProg1.textContent = t1 || 'Program 1';
    tabProg2.textContent = t2 || 'Program 2';
  }

  function persistProgramScopedInputs(program){
    programScopedIds.forEach((id) => {
      const el = document.getElementById(id);
      if (!el) return;
      currentState[programKey(id, program)] = el.value;
      currentState[id] = el.value;
    });
  }

  function applyProgramScopedInputs(program){
    programScopedIds.forEach((id) => {
      const el = document.getElementById(id);
      if (!el) return;
      const v = currentState[programKey(id, program)] || currentState[id] || el.value;
      el.value = v;
    });
  }

  function setActiveProgram(program){
    if (program !== 1 && program !== 2) program = 1;
    persistProgramScopedInputs(activeProgram);
    activeProgram = program;
    currentState.active_program = activeProgram;
    applyProgramScopedInputs(activeProgram);
    tabProg1.classList.toggle('active', activeProgram === 1);
    tabProg2.classList.toggle('active', activeProgram === 2);
    document.querySelectorAll('.program-field').forEach((el) => {
      const show = (activeTab !== 'global') && el.classList.contains(`program-${activeProgram}`);
      el.classList.toggle('active', show);
    });
  }

  function setActiveTab(tab){
    if (!['program1','program2','global'].includes(tab)) tab = 'program1';
    activeTab = tab;
    currentState.active_tab = activeTab;
    tabProg1.classList.toggle('active', tab === 'program1');
    tabProg2.classList.toggle('active', tab === 'program2');
    tabGlobal.classList.toggle('active', tab === 'global');
    document.querySelectorAll('.global-field').forEach((el) => {
      el.classList.toggle('active', tab === 'global');
    });
    setActiveProgram(activeProgram);
  }

  async function loadState(){
    const res = await fetch('/api/state');
    const data = await res.json();
    currentState = data || {};
    ids.forEach((id)=>{
      if(programScopedIds.includes(id)) return;
      if(data[id] !== undefined){ document.getElementById(id).value = data[id]; }
    });
    boolStateIds.forEach((id)=>{
      if(data[id] !== undefined){ document.getElementById(id).checked = !!data[id]; }
    });
    updateTabTitles();
    setActiveProgram(Number(data.active_program || 1));
    setActiveTab(String(data.active_tab || `program${Number(data.active_program || 1)}`));
    updateWaveWindowReadout();
    updateMomentaryControlVisibility();
    applyTheme(data.ui_theme || 'forest');
    applyCustomCss(data.ui_custom_css || '');
    await loadRdsState();
    refreshPreview();
  }

  async function loadRdsState(){
    const res = await fetch('/api/rds_state');
    const data = await res.json();
    const activeId = document.activeElement ? document.activeElement.id : '';
    rdsIds.forEach((id)=>{
      if(data[id] !== undefined && activeId !== id){
        document.getElementById(id).value = data[id];
      }
    });
    rdsBoolIds.forEach((id)=>{
      if(data[id] !== undefined && activeId !== id){
        document.getElementById(id).checked = !!data[id];
      }
    });
    rdsLiveTextIds.forEach((id)=>{
      if(data[id] !== undefined){
        document.getElementById(id).textContent = data[id] || '-';
      }
    });
  }

  function collect(){
    const payload = {};
    ids.forEach((id)=>{
      if(programScopedIds.includes(id)) return;
      payload[id] = document.getElementById(id).value;
    });
    boolStateIds.forEach((id)=>{
      payload[id] = document.getElementById(id).checked;
    });
    payload.active_program = activeProgram;
    payload.active_tab = activeTab;
    programScopedIds.forEach((id) => {
      const v = document.getElementById(id).value;
      payload[id] = v;
      payload[programKey(id, activeProgram)] = v;
      currentState[programKey(id, activeProgram)] = v;
      currentState[id] = v;
    });
    return payload;
  }

  async function saveState(){
    await fetch('/api/state', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(collect())});
  }

  function collectRds(){
    const payload = {};
    rdsIds.forEach((id)=> payload[id] = document.getElementById(id).value);
    rdsBoolIds.forEach((id)=> payload[id] = document.getElementById(id).checked);
    return payload;
  }

  async function saveRdsState(){
    await fetch('/api/rds_state', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(collectRds())});
  }

  function applyTheme(themeName){
    const palette = themePalettes[themeName] || themePalettes.forest;
    Object.keys(palette).forEach((k) => document.documentElement.style.setProperty(k, palette[k]));
  }

  function applyCustomCss(cssText){
    customCssTag.textContent = cssText || '';
  }

  function updateFftMarkers(){
    const maxHz = Number(document.getElementById('fft_max_hz').value || 60000);
    const pilotPct = Math.max(0, Math.min(100, (19000 / maxHz) * 100));
    const subPct = Math.max(0, Math.min(100, (38000 / maxHz) * 100));
    pilotMarker.style.left = `${pilotPct}%`;
    subMarker.style.left = `${subPct}%`;
  }

  function refreshFft(){
    updateFftMarkers();
    fftImg.src = '/api/mpx_fft.png?program=' + activeProgram + '&ts=' + Date.now();
  }

  function startFftLoop(){
    if (fftTimer) clearInterval(fftTimer);
    fftTimer = setInterval(() => {
      if (!analysisPaused) refreshFft();
    }, 1200);
  }

  function startRdsLoop(){
    setInterval(() => {
      loadRdsState().catch(()=>{});
    }, 2000);
  }

  function refreshPreview(){
    audio.src = '/api/preview.mp3?program=' + activeProgram + '&ts=' + Date.now();
    audio.play().catch(()=>{});
    setStatus('Preview refreshed.');
  }

  fftImg.onerror = () => {
    setStatus('FFT unavailable for current source. Try an input or stream source with active audio.');
  };

  function captureWaveHistory(){
    waveFrameCounter += 1;
    if (waveFrameCounter % 2 !== 0) return;
    const stride = Math.max(1, Math.floor(timeData.length / WAVE_POINTS_PER_FRAME));
    for(let i=0;i<timeData.length;i+=stride){
      const v = (timeData[i] - 128) / 128;
      waveHistory.push(v);
    }
    const approxFps = 30;
    const maxLen = Math.floor(WAVE_HISTORY_MAX_SECONDS * approxFps * WAVE_POINTS_PER_FRAME);
    if (waveHistory.length > maxLen) {
      waveHistory.splice(0, waveHistory.length - maxLen);
    }
  }

  function drawWaveFromHistory(){
    const windowSec = Number(document.getElementById('wave_window_sec').value || 3);
    const approxFps = 30;
    const wanted = Math.max(120, Math.floor(windowSec * approxFps * WAVE_POINTS_PER_FRAME));
    const start = Math.max(0, waveHistory.length - wanted);
    const data = waveHistory.slice(start);
    wctx.fillStyle = '#07110f';
    wctx.fillRect(0,0,wave.width,wave.height);
    if (data.length < 2) return;
    wctx.strokeStyle = '#f2b642';
    wctx.lineWidth = 2;
    wctx.beginPath();
    const step = wave.width / (data.length - 1);
    for(let i=0;i<data.length;i++){
      const y = (0.5 - (data[i] * 0.45)) * wave.height;
      if(i===0) wctx.moveTo(0,y); else wctx.lineTo(i*step,y);
    }
    wctx.stroke();
  }

  tabProg1.onclick = async () => { setActiveProgram(1); setActiveTab('program1'); await saveState(); refreshPreview(); };
  tabProg2.onclick = async () => { setActiveProgram(2); setActiveTab('program2'); await saveState(); refreshPreview(); };
  tabGlobal.onclick = async () => { setActiveTab('global'); await saveState(); };
  document.getElementById('tab_name_prog1').addEventListener('input', updateTabTitles);
  document.getElementById('tab_name_prog2').addEventListener('input', updateTabTitles);
  enableMomentaryAbCtl.addEventListener('change', () => {
    updateMomentaryControlVisibility();
    saveState().catch(()=>{});
  });
  waveWindowCtl.addEventListener('input', () => {
    updateWaveWindowReadout();
    saveState().catch(()=>{});
  });
  processingBypassToggleBtn.onclick = async () => {
    processingBypassCtl.checked = !processingBypassCtl.checked;
    await saveState();
    refreshPreview();
    setStatus(processingBypassCtl.checked ? 'Processing bypass enabled.' : 'Processing bypass disabled.');
  };
  const holdStart = async () => {
    if (!enableMomentaryAbCtl.checked) return;
    bypassBeforeHold = processingBypassCtl.checked;
    if (!processingBypassCtl.checked) {
      processingBypassCtl.checked = true;
      await saveState();
      refreshPreview();
      setStatus('Momentary bypass active.');
    }
  };
  const holdEnd = async () => {
    if (bypassBeforeHold === null) return;
    const target = !!bypassBeforeHold;
    bypassBeforeHold = null;
    if (processingBypassCtl.checked !== target) {
      processingBypassCtl.checked = target;
      await saveState();
      refreshPreview();
    }
    setStatus('Momentary bypass released.');
  };
  processingBypassHoldBtn.addEventListener('mousedown', () => { holdStart().catch(()=>{}); });
  processingBypassHoldBtn.addEventListener('mouseup', () => { holdEnd().catch(()=>{}); });
  processingBypassHoldBtn.addEventListener('mouseleave', () => { holdEnd().catch(()=>{}); });
  processingBypassHoldBtn.addEventListener('touchstart', (e) => { e.preventDefault(); holdStart().catch(()=>{}); }, {passive:false});
  processingBypassHoldBtn.addEventListener('touchend', (e) => { e.preventDefault(); holdEnd().catch(()=>{}); }, {passive:false});
  processingBypassHoldBtn.addEventListener('touchcancel', (e) => { e.preventDefault(); holdEnd().catch(()=>{}); }, {passive:false});
  analysisPauseBtn.onclick = () => {
    analysisPaused = !analysisPaused;
    analysisPauseBtn.textContent = analysisPaused ? 'Resume Scope' : 'Pause Scope';
    setStatus(analysisPaused ? 'Scope paused.' : 'Scope resumed.');
  };
  analysisStepBtn.onclick = () => {
    if (!analysisPaused) {
      analysisPaused = true;
      analysisPauseBtn.textContent = 'Resume Scope';
    }
    renderAnalysisFrame();
    refreshFft();
    setStatus('Stepped one analysis frame.');
  };

  document.getElementById('apply').onclick = async () => {
    await saveState();
    refreshPreview();
    refreshFft();
  };
  document.getElementById('patch_start').onclick = async () => {
    await saveState();
    const r = await fetch('/api/patch/start', {method:'POST'});
    const j = await r.json();
    setStatus(j.message || 'Patch started.');
  };
  document.getElementById('patch_stop').onclick = async () => {
    const r = await fetch('/api/patch/stop', {method:'POST'});
    const j = await r.json();
    setStatus(j.message || 'Patch stopped.');
  };
  document.getElementById('fft_refresh').onclick = async () => {
    await saveState();
    refreshFft();
    setStatus('FFT refreshed.');
  };
  document.getElementById('theme_apply').onclick = async () => {
    const theme = document.getElementById('ui_theme').value || 'forest';
    applyTheme(theme);
    await saveState();
    setStatus('Theme applied.');
  };
  document.getElementById('css_apply').onclick = async () => {
    const cssText = document.getElementById('ui_custom_css').value || '';
    applyCustomCss(cssText);
    await saveState();
    setStatus('Custom CSS applied.');
  };
  document.getElementById('rds_apply').onclick = async () => {
    await saveRdsState();
    await loadRdsState().catch(()=>{});
    setStatus('RDS overrides applied. rds-sync services will use them on next sync cycle.');
  };

  const ctx = new (window.AudioContext || window.webkitAudioContext)();
  const src = ctx.createMediaElementSource(audio);
  const analyser = ctx.createAnalyser();
  analyser.fftSize = 2048;
  src.connect(analyser);
  analyser.connect(ctx.destination);

  const wave = document.getElementById('wave');
  const spec = document.getElementById('spec');
  const wctx = wave.getContext('2d');
  const sctx = spec.getContext('2d');
  const timeData = new Uint8Array(analyser.fftSize);
  const freqData = new Uint8Array(analyser.frequencyBinCount);
  const bandDefs = [
    {name:'sub', lo:30, hi:120},
    {name:'low', lo:120, hi:400},
    {name:'mid', lo:400, hi:2000},
    {name:'pres', lo:2000, hi:6000},
    {name:'air', lo:6000, hi:15000},
  ];

  function updateBandMeters(){
    const nyquist = ctx.sampleRate / 2;
    const hzPerBin = nyquist / freqData.length;
    bandDefs.forEach((b) => {
      const start = Math.max(0, Math.floor(b.lo / hzPerBin));
      const end = Math.min(freqData.length - 1, Math.ceil(b.hi / hzPerBin));
      let sum = 0;
      let n = 0;
      for(let i=start;i<=end;i++){
        sum += freqData[i] || 0;
        n++;
      }
      const avg = n > 0 ? (sum / n) : 0;
      const linear = Math.max(1e-6, avg / 255);
      const db = 20 * Math.log10(linear);
      const clampedDb = Math.max(-60, Math.min(0, db));
      const pct = ((clampedDb + 60) / 60) * 100;
      const fill = document.getElementById(`meter_${b.name}`);
      const label = document.getElementById(`meter_${b.name}_db`);
      if(fill) fill.style.width = `${pct.toFixed(1)}%`;
      if(label) label.textContent = `${db.toFixed(1)} dB`;
    });
  }

  function renderAnalysisFrame(){
    analyser.getByteTimeDomainData(timeData);
    captureWaveHistory();
    drawWaveFromHistory();

    analyser.getByteFrequencyData(freqData);
    sctx.fillStyle = '#07110f';
    sctx.fillRect(0,0,spec.width,spec.height);
    const bars = 64;
    const bin = Math.floor(freqData.length / bars);
    const peakHoldEnabled = !!document.getElementById('peak_hold_enabled').checked;
    const peakDecay = Math.max(0.5, Math.min(0.999, Number(document.getElementById('peak_hold_decay').value || 0.94)));
    for(let i=0;i<bars;i++){
    let sum = 0;
    for(let j=0;j<bin;j++) sum += freqData[i*bin + j] || 0;
    const avg = sum / bin;
    const h = (avg/255) * spec.height;
    sctx.fillStyle = `hsl(${45 + i*1.6}, 80%, ${35 + (avg/255)*35}%)`;
    const bw = spec.width / bars;
    sctx.fillRect(i*bw, spec.height - h, bw-2, h);
    if (peakHoldEnabled) {
      peakBars[i] = Math.max(h, peakBars[i] * peakDecay);
      sctx.fillStyle = '#7ef2d0';
      sctx.fillRect(i*bw, spec.height - peakBars[i], bw-2, 2);
    } else {
      peakBars[i] = h;
    }
    }
    updateBandMeters();
  }

  function draw(){
    requestAnimationFrame(draw);
    if (analysisPaused) return;
    renderAnalysisFrame();
  }

  document.body.addEventListener('click', () => ctx.resume(), {once:true});
  loadState().then(() => {
    draw();
    refreshFft();
    startFftLoop();
    startRdsLoop();
  });
  </script>
</body>
</html>"""


def shutdown_handler(signum, frame):
  with PATCH_LOCK:
    stop_patch_playback()
  raise SystemExit(0)


if __name__ == "__main__":
  signal.signal(signal.SIGTERM, shutdown_handler)
  signal.signal(signal.SIGINT, shutdown_handler)
  os.umask(0o077)
  with STATE_LOCK:
    state = load_state()
    save_state(state)
  server = ThreadingHTTPServer((BIND, PORT), Handler)
  server.serve_forever()
OMPXWEB
chown "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}/ompx-web-ui.py"
chmod 750 "${SYS_SCRIPTS_DIR}/ompx-web-ui.py"

cat > "${OMPX_WEB_UI_SERVICE}" <<EOF
[Unit]
Description=oMPX live web control UI
After=network-online.target sound.target
Wants=network-online.target sound.target

[Service]
Type=simple
User=${OMPX_USER}
Group=${OMPX_USER}
SupplementaryGroups=audio
WorkingDirectory=${OMPX_HOME}
Environment=HOME=${OMPX_HOME}
ExecStart=/usr/bin/python3 ${SYS_SCRIPTS_DIR}/ompx-web-ui.py
Restart=on-failure
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "${OMPX_WEB_UI_SERVICE}"
chown root:root "${OMPX_WEB_UI_SERVICE}"
echo "[SUCCESS] oMPX web UI service files created"

cat > "${SYS_SCRIPTS_DIR}/ompx-web-kiosk.sh" <<'KIOSK'
#!/usr/bin/env bash
set -euo pipefail

PROFILE="/home/ompx/.profile"
[ -f "${PROFILE}" ] && . "${PROFILE}"

OMPX_WEB_KIOSK_ENABLE="${OMPX_WEB_KIOSK_ENABLE:-false}"
OMPX_WEB_KIOSK_DISPLAY="${OMPX_WEB_KIOSK_DISPLAY:-:0}"
OMPX_WEB_KIOSK_URL="${OMPX_WEB_KIOSK_URL:-http://127.0.0.1:${OMPX_WEB_PORT:-8082}/}"
XAUTHORITY="${XAUTHORITY:-/home/ompx/.Xauthority}"

if [ "${OMPX_WEB_KIOSK_ENABLE}" != "true" ]; then
  exit 0
fi

CHROMIUM_BIN=""
for candidate in chromium chromium-browser google-chrome; do
  if command -v "${candidate}" >/dev/null 2>&1; then
    CHROMIUM_BIN="${candidate}"
    break
  fi
done

if [ -z "${CHROMIUM_BIN}" ]; then
  echo "[kiosk] chromium binary not found" >&2
  exit 1
fi

export DISPLAY="${OMPX_WEB_KIOSK_DISPLAY}"
export XAUTHORITY

for _ in $(seq 1 30); do
  if [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ] || [ -d /tmp/.X11-unix ]; then
    break
  fi
  sleep 1
done

for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 "${OMPX_WEB_KIOSK_URL}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

pkill -u "$(id -un)" -f 'chromium|chromium-browser|google-chrome' >/dev/null 2>&1 || true

exec "${CHROMIUM_BIN}" \
  --kiosk "${OMPX_WEB_KIOSK_URL}" \
  --noerrdialogs \
  --disable-session-crashed-bubble \
  --disable-infobars \
  --autoplay-policy=no-user-gesture-required \
  --check-for-update-interval=31536000
KIOSK
chown "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}/ompx-web-kiosk.sh"
chmod 750 "${SYS_SCRIPTS_DIR}/ompx-web-kiosk.sh"

cat > "${OMPX_WEB_KIOSK_SERVICE}" <<EOF
[Unit]
Description=oMPX local Chromium kiosk
After=network-online.target ompx-web-ui.service
Wants=network-online.target ompx-web-ui.service

[Service]
Type=simple
User=${OMPX_USER}
Group=${OMPX_USER}
WorkingDirectory=${OMPX_HOME}
Environment=HOME=${OMPX_HOME}
ExecStart=${SYS_SCRIPTS_DIR}/ompx-web-kiosk.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "${OMPX_WEB_KIOSK_SERVICE}"
chown root:root "${OMPX_WEB_KIOSK_SERVICE}"
echo "[SUCCESS] oMPX web kiosk service files created"

# --- RDS sync (Program 1) ---
echo "[INFO] Creating Program 1 RDS sync script..."
cat > "${SYS_SCRIPTS_DIR}/rds-sync-prog1.sh" <<'RDS1'
#!/usr/bin/env bash
set -euo pipefail

PROFILE="/home/ompx/.profile"
[ -f "${PROFILE}" ] && . "${PROFILE}"

RDS_PROG1_ENABLE="${RDS_PROG1_ENABLE:-false}"
RDS_PROG1_SOURCE="${RDS_PROG1_SOURCE:-url}"
RDS_PROG1_RT_URL="${RDS_PROG1_RT_URL:-}"
RDS_PROG1_ICECAST_STATS_URL="${RDS_PROG1_ICECAST_STATS_URL:-}"
RDS_PROG1_ICECAST_MOUNT="${RDS_PROG1_ICECAST_MOUNT:-}"
RDS_PROG1_INTERVAL_SEC="${RDS_PROG1_INTERVAL_SEC:-5}"
RDS_PROG1_RT_PATH="${RDS_PROG1_RT_PATH:-/home/ompx/rds/prog1/rt.txt}"
RDS_PROG1_PS="${RDS_PROG1_PS:-OMPXFM1}"
RDS_PROG1_PI="${RDS_PROG1_PI:-1A01}"
RDS_PROG1_PTY="${RDS_PROG1_PTY:-10}"
RDS_PROG1_TP="${RDS_PROG1_TP:-true}"
RDS_PROG1_TA="${RDS_PROG1_TA:-false}"
RDS_PROG1_MS="${RDS_PROG1_MS:-true}"
RDS_PROG1_CT_ENABLE="${RDS_PROG1_CT_ENABLE:-true}"
RDS_PROG1_CT_MODE="${RDS_PROG1_CT_MODE:-local}"
RDS_PROG1_INFO_PATH="${RDS_PROG1_INFO_PATH:-/home/ompx/rds/prog1/rds-info.json}"
RDS_PROG1_OVERRIDE_PATH="${RDS_PROG1_OVERRIDE_PATH:-/home/ompx/rds/prog1/rds-override.json}"
RADIO1_URL="${RADIO1_URL:-}"

_log(){ logger -t rds-sync-prog1 "$*"; echo "$(date +'%F %T') [rds-sync-prog1] $*"; }

json_escape(){
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  s="${s//$'\t'/ }"
  printf '%s' "$s"
}

write_rds_info(){
  local rt_text="$1"
  local ct_text=""
  local ps pi pty tp ta ms
  local info_tmp

  ps="${RDS_PROG1_PS:0:8}"
  pi="${RDS_PROG1_PI^^}"
  pty="${RDS_PROG1_PTY}"
  tp="${RDS_PROG1_TP,,}"
  ta="${RDS_PROG1_TA,,}"
  ms="${RDS_PROG1_MS,,}"

  [ "${tp}" = "true" ] || tp="false"
  [ "${ta}" = "true" ] || ta="false"
  [ "${ms}" = "true" ] || ms="false"
  if ! [[ "${pi}" =~ ^[0-9A-F]{4}$ ]]; then pi="1A01"; fi
  if ! [[ "${pty}" =~ ^[0-9]+$ ]] || [ "${pty}" -lt 0 ] || [ "${pty}" -gt 31 ]; then pty="10"; fi

  if [ "${RDS_PROG1_CT_ENABLE,,}" = "true" ]; then
    if [ "${RDS_PROG1_CT_MODE,,}" = "utc" ]; then
      ct_text="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    else
      ct_text="$(date +'%Y-%m-%dT%H:%M:%S%z')"
    fi
  fi

  mkdir -p "$(dirname "${RDS_PROG1_INFO_PATH}")"
  info_tmp="${RDS_PROG1_INFO_PATH}.tmp"
  cat > "${info_tmp}" <<INFO
{
  "program": 1,
  "ps": "$(json_escape "${ps}")",
  "pi": "${pi}",
  "pty": ${pty},
  "tp": ${tp},
  "ta": ${ta},
  "ms": ${ms},
  "ct": "$(json_escape "${ct_text}")",
  "rt": "$(json_escape "${rt_text}")",
  "updated_at": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
}
INFO
  mv -f "${info_tmp}" "${RDS_PROG1_INFO_PATH}"
}

load_override(){
  OV_PS=""; OV_PI=""; OV_PTY=""; OV_TP=""; OV_TA=""; OV_MS=""; OV_CT_ENABLE=""; OV_CT_MODE=""; OV_RT=""
  [ -s "${RDS_PROG1_OVERRIDE_PATH}" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  eval "$(python3 - "${RDS_PROG1_OVERRIDE_PATH}" <<'PY'
import json
import shlex
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {}

def emit(key, value):
    if value is None:
        return
    print(f"{key}={shlex.quote(str(value))}")

emit("OV_PS", str(data.get("ps", ""))[:8])
emit("OV_PI", str(data.get("pi", "")).upper())
emit("OV_PTY", data.get("pty", ""))
emit("OV_TP", str(data.get("tp", "")).lower())
emit("OV_TA", str(data.get("ta", "")).lower())
emit("OV_MS", str(data.get("ms", "")).lower())
emit("OV_CT_ENABLE", str(data.get("ct_enable", "")).lower())
emit("OV_CT_MODE", str(data.get("ct_mode", "")).lower())
emit("OV_RT", data.get("rt", ""))
PY
)" || true
}

_fetch_stream_title(){
  local stream_url="$1"
  local title=""
  title="$(timeout 20 ffprobe -v error -show_entries format_tags:stream_tags -of default=noprint_wrappers=1:nokey=0 "${stream_url}" 2>/dev/null | awk 'BEGIN{IGNORECASE=1} /^TAG:(StreamTitle|title)=/ {sub(/^[^=]*=/,""); print; exit}' | tr -d '\r' || true)"
  if [ -z "${title}" ]; then
    title="$(timeout 20 ffmpeg -nostdin -hide_banner -loglevel info -headers "Icy-MetaData:1" -i "${stream_url}" -t 12 -vn -sn -dn -f null - 2>&1 | sed -n "s/.*StreamTitle='\([^']*\)'.*/\1/p" | head -n1 | tr -d '\r' || true)"
  fi
  if [ -z "${title}" ]; then
    title="$(timeout 20 ffmpeg -nostdin -hide_banner -loglevel info -headers "Icy-MetaData:1" -i "${stream_url}" -t 12 -vn -sn -dn -f null - 2>&1 | sed -n "s/.*[Tt][Ii][Tt][Ll][Ee][[:space:]]*:[[:space:]]*\(.*\)$/\1/p" | head -n1 | tr -d '\r' || true)"
  fi
  printf '%s' "${title}"
}

_fetch_icecast_title(){
  local stats_url="$1"
  local mount="$2"
  local title=""
  if command -v jq >/dev/null 2>&1; then
    title="$(curl -sf --max-time 15 "${stats_url}" 2>/dev/null | jq -r --arg m "${mount}" '.icestats.source | if type=="array" then .[] else . end | select(.listenurl | contains($m)) | .title // ""' 2>/dev/null | head -n1 | tr -d '\r' || true)"
  elif command -v python3 >/dev/null 2>&1; then
    title="$(curl -sf --max-time 15 "${stats_url}" 2>/dev/null | python3 -c "
import sys, json
try:
    data=json.load(sys.stdin)
    src=data['icestats']['source']
    if not isinstance(src,list): src=[src]
    mount=sys.argv[1]
    for s in src:
        if mount in s.get('listenurl',''):
            print(s.get('title',s.get('artist',''))); break
except: pass" "${mount}" 2>/dev/null | tr -d '\r' || true)"
  fi
  printf '%s' "${title}"
}

if [ "${RDS_PROG1_ENABLE}" != "true" ]; then
  _log "RDS_PROG1_ENABLE is not true; exiting"
  exit 0
fi

if [ "${RDS_PROG1_SOURCE}" = "metadata" ] && [ -z "${RADIO1_URL}" ]; then
  _log "RDS_PROG1_SOURCE=metadata but RADIO1_URL is empty; exiting"
  exit 0
fi

if [ "${RDS_PROG1_SOURCE}" = "icecast" ] && { [ -z "${RDS_PROG1_ICECAST_STATS_URL}" ] || [ -z "${RDS_PROG1_ICECAST_MOUNT}" ]; }; then
  _log "RDS_PROG1_SOURCE=icecast but ICECAST_STATS_URL or ICECAST_MOUNT is empty; exiting"
  exit 0
fi

if [ "${RDS_PROG1_SOURCE}" = "url" ] && [ -z "${RDS_PROG1_RT_URL}" ]; then
  _log "RDS_PROG1_RT_URL is empty; exiting"
  exit 0
fi

if ! [[ "${RDS_PROG1_INTERVAL_SEC}" =~ ^[0-9]+$ ]] || [ "${RDS_PROG1_INTERVAL_SEC}" -lt 1 ]; then
  RDS_PROG1_INTERVAL_SEC=5
fi

mkdir -p "$(dirname "${RDS_PROG1_RT_PATH}")"
touch "${RDS_PROG1_RT_PATH}" 2>/dev/null || true
tmp_path="${RDS_PROG1_RT_PATH}.tmp"
current_rt=""

while true; do
  if [ "${RDS_PROG1_SOURCE}" = "metadata" ]; then
    rt_text="$(_fetch_stream_title "${RADIO1_URL}")"
    if [ -n "${rt_text}" ]; then
      printf '%s\n' "${rt_text}" > "${tmp_path}"
      mv -f "${tmp_path}" "${RDS_PROG1_RT_PATH}"
    else
      _log "No StreamTitle metadata found from RADIO1_URL"
      rt_text=""
    fi
  elif [ "${RDS_PROG1_SOURCE}" = "icecast" ]; then
    rt_text="$(_fetch_icecast_title "${RDS_PROG1_ICECAST_STATS_URL}" "${RDS_PROG1_ICECAST_MOUNT}")"
    if [ -n "${rt_text}" ]; then
      printf '%s\n' "${rt_text}" > "${tmp_path}"
      mv -f "${tmp_path}" "${RDS_PROG1_RT_PATH}"
    else
      _log "No title from Icecast stats at ${RDS_PROG1_ICECAST_STATS_URL} mount ${RDS_PROG1_ICECAST_MOUNT}"
      rt_text=""
    fi
  else
    if wget -q -T 20 -O "${tmp_path}" "${RDS_PROG1_RT_URL}"; then
      if [ -s "${tmp_path}" ] && grep -q '[^[:space:]]' "${tmp_path}" 2>/dev/null; then
        mv -f "${tmp_path}" "${RDS_PROG1_RT_PATH}"
        rt_text="$(head -n1 "${RDS_PROG1_RT_PATH}" 2>/dev/null || true)"
      else
        rm -f "${tmp_path}" || true
        _log "Fetched empty RT from ${RDS_PROG1_RT_URL}; keeping previous file contents"
        rt_text=""
      fi
    else
      _log "Failed to fetch ${RDS_PROG1_RT_URL}"
      rt_text=""
    fi
  fi

  if [ -n "${rt_text}" ]; then
    current_rt="${rt_text}"
  elif [ -z "${current_rt}" ] && [ -s "${RDS_PROG1_RT_PATH}" ]; then
    current_rt="$(head -n1 "${RDS_PROG1_RT_PATH}" 2>/dev/null || true)"
  fi

  load_override
  [ -n "${OV_PS}" ] && RDS_PROG1_PS="${OV_PS:0:8}"
  if [ -n "${OV_PI}" ] && [[ "${OV_PI}" =~ ^[0-9A-F]{4}$ ]]; then RDS_PROG1_PI="${OV_PI}"; fi
  if [ -n "${OV_PTY}" ] && [[ "${OV_PTY}" =~ ^[0-9]+$ ]] && [ "${OV_PTY}" -ge 0 ] && [ "${OV_PTY}" -le 31 ]; then RDS_PROG1_PTY="${OV_PTY}"; fi
  [ "${OV_TP}" = "true" ] && RDS_PROG1_TP="true"
  [ "${OV_TP}" = "false" ] && RDS_PROG1_TP="false"
  [ "${OV_TA}" = "true" ] && RDS_PROG1_TA="true"
  [ "${OV_TA}" = "false" ] && RDS_PROG1_TA="false"
  [ "${OV_MS}" = "true" ] && RDS_PROG1_MS="true"
  [ "${OV_MS}" = "false" ] && RDS_PROG1_MS="false"
  [ "${OV_CT_ENABLE}" = "true" ] && RDS_PROG1_CT_ENABLE="true"
  [ "${OV_CT_ENABLE}" = "false" ] && RDS_PROG1_CT_ENABLE="false"
  [ "${OV_CT_MODE}" = "utc" ] && RDS_PROG1_CT_MODE="utc"
  [ "${OV_CT_MODE}" = "local" ] && RDS_PROG1_CT_MODE="local"
  if [ -n "${OV_RT}" ]; then
    current_rt="${OV_RT}"
    printf '%s\n' "${current_rt}" > "${tmp_path}"
    mv -f "${tmp_path}" "${RDS_PROG1_RT_PATH}"
  fi

  write_rds_info "${current_rt}"

  sleep "${RDS_PROG1_INTERVAL_SEC}"
done
RDS1
chown "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}/rds-sync-prog1.sh"
chmod 750 "${SYS_SCRIPTS_DIR}/rds-sync-prog1.sh"
echo "[SUCCESS] Created ${SYS_SCRIPTS_DIR}/rds-sync-prog1.sh"

cat > "${RDS_SYNC_PROG1_SERVICE}" <<EOF
[Unit]
Description=oMPX Program 1 RDS text sync
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${OMPX_USER}
Group=${OMPX_USER}
WorkingDirectory=${OMPX_HOME}
Environment=HOME=${OMPX_HOME}
ExecStart=${SYS_SCRIPTS_DIR}/rds-sync-prog1.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "${RDS_SYNC_PROG1_SERVICE}"
chown root:root "${RDS_SYNC_PROG1_SERVICE}"
echo "[SUCCESS] Installed rds-sync-prog1.service"

# --- RDS sync (Program 2) ---
echo "[INFO] Creating Program 2 RDS sync script..."
cat > "${SYS_SCRIPTS_DIR}/rds-sync-prog2.sh" <<'RDS2'
#!/usr/bin/env bash
set -euo pipefail

PROFILE="/home/ompx/.profile"
[ -f "${PROFILE}" ] && . "${PROFILE}"

RDS_PROG2_ENABLE="${RDS_PROG2_ENABLE:-false}"
RDS_PROG2_SOURCE="${RDS_PROG2_SOURCE:-url}"
RDS_PROG2_RT_URL="${RDS_PROG2_RT_URL:-}"
RDS_PROG2_ICECAST_STATS_URL="${RDS_PROG2_ICECAST_STATS_URL:-}"
RDS_PROG2_ICECAST_MOUNT="${RDS_PROG2_ICECAST_MOUNT:-}"
RDS_PROG2_INTERVAL_SEC="${RDS_PROG2_INTERVAL_SEC:-5}"
RDS_PROG2_RT_PATH="${RDS_PROG2_RT_PATH:-/home/ompx/rds/prog2/rt.txt}"
RDS_PROG2_PS="${RDS_PROG2_PS:-OMPXFM2}"
RDS_PROG2_PI="${RDS_PROG2_PI:-1A02}"
RDS_PROG2_PTY="${RDS_PROG2_PTY:-10}"
RDS_PROG2_TP="${RDS_PROG2_TP:-true}"
RDS_PROG2_TA="${RDS_PROG2_TA:-false}"
RDS_PROG2_MS="${RDS_PROG2_MS:-true}"
RDS_PROG2_CT_ENABLE="${RDS_PROG2_CT_ENABLE:-true}"
RDS_PROG2_CT_MODE="${RDS_PROG2_CT_MODE:-local}"
RDS_PROG2_INFO_PATH="${RDS_PROG2_INFO_PATH:-/home/ompx/rds/prog2/rds-info.json}"
RDS_PROG2_OVERRIDE_PATH="${RDS_PROG2_OVERRIDE_PATH:-/home/ompx/rds/prog2/rds-override.json}"
RADIO2_URL="${RADIO2_URL:-}"

_log(){ logger -t rds-sync-prog2 "$*"; echo "$(date +'%F %T') [rds-sync-prog2] $*"; }

json_escape(){
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  s="${s//$'\t'/ }"
  printf '%s' "$s"
}

write_rds_info(){
  local rt_text="$1"
  local ct_text=""
  local ps pi pty tp ta ms
  local info_tmp

  ps="${RDS_PROG2_PS:0:8}"
  pi="${RDS_PROG2_PI^^}"
  pty="${RDS_PROG2_PTY}"
  tp="${RDS_PROG2_TP,,}"
  ta="${RDS_PROG2_TA,,}"
  ms="${RDS_PROG2_MS,,}"

  [ "${tp}" = "true" ] || tp="false"
  [ "${ta}" = "true" ] || ta="false"
  [ "${ms}" = "true" ] || ms="false"
  if ! [[ "${pi}" =~ ^[0-9A-F]{4}$ ]]; then pi="1A02"; fi
  if ! [[ "${pty}" =~ ^[0-9]+$ ]] || [ "${pty}" -lt 0 ] || [ "${pty}" -gt 31 ]; then pty="10"; fi

  if [ "${RDS_PROG2_CT_ENABLE,,}" = "true" ]; then
    if [ "${RDS_PROG2_CT_MODE,,}" = "utc" ]; then
      ct_text="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    else
      ct_text="$(date +'%Y-%m-%dT%H:%M:%S%z')"
    fi
  fi

  mkdir -p "$(dirname "${RDS_PROG2_INFO_PATH}")"
  info_tmp="${RDS_PROG2_INFO_PATH}.tmp"
  cat > "${info_tmp}" <<INFO
{
  "program": 2,
  "ps": "$(json_escape "${ps}")",
  "pi": "${pi}",
  "pty": ${pty},
  "tp": ${tp},
  "ta": ${ta},
  "ms": ${ms},
  "ct": "$(json_escape "${ct_text}")",
  "rt": "$(json_escape "${rt_text}")",
  "updated_at": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
}
INFO
  mv -f "${info_tmp}" "${RDS_PROG2_INFO_PATH}"
}

load_override(){
  OV_PS=""; OV_PI=""; OV_PTY=""; OV_TP=""; OV_TA=""; OV_MS=""; OV_CT_ENABLE=""; OV_CT_MODE=""; OV_RT=""
  [ -s "${RDS_PROG2_OVERRIDE_PATH}" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  eval "$(python3 - "${RDS_PROG2_OVERRIDE_PATH}" <<'PY'
import json
import shlex
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {}

def emit(key, value):
    if value is None:
        return
    print(f"{key}={shlex.quote(str(value))}")

emit("OV_PS", str(data.get("ps", ""))[:8])
emit("OV_PI", str(data.get("pi", "")).upper())
emit("OV_PTY", data.get("pty", ""))
emit("OV_TP", str(data.get("tp", "")).lower())
emit("OV_TA", str(data.get("ta", "")).lower())
emit("OV_MS", str(data.get("ms", "")).lower())
emit("OV_CT_ENABLE", str(data.get("ct_enable", "")).lower())
emit("OV_CT_MODE", str(data.get("ct_mode", "")).lower())
emit("OV_RT", data.get("rt", ""))
PY
)" || true
}

_fetch_stream_title(){
  local stream_url="$1"
  local title=""
  title="$(timeout 20 ffprobe -v error -show_entries format_tags:stream_tags -of default=noprint_wrappers=1:nokey=0 "${stream_url}" 2>/dev/null | awk 'BEGIN{IGNORECASE=1} /^TAG:(StreamTitle|title)=/ {sub(/^[^=]*=/,""); print; exit}' | tr -d '\r' || true)"
  if [ -z "${title}" ]; then
    title="$(timeout 20 ffmpeg -nostdin -hide_banner -loglevel info -headers "Icy-MetaData:1" -i "${stream_url}" -t 12 -vn -sn -dn -f null - 2>&1 | sed -n "s/.*StreamTitle='\([^']*\)'.*/\1/p" | head -n1 | tr -d '\r' || true)"
  fi
  if [ -z "${title}" ]; then
    title="$(timeout 20 ffmpeg -nostdin -hide_banner -loglevel info -headers "Icy-MetaData:1" -i "${stream_url}" -t 12 -vn -sn -dn -f null - 2>&1 | sed -n "s/.*[Tt][Ii][Tt][Ll][Ee][[:space:]]*:[[:space:]]*\(.*\)$/\1/p" | head -n1 | tr -d '\r' || true)"
  fi
  printf '%s' "${title}"
}

_fetch_icecast_title(){
  local stats_url="$1"
  local mount="$2"
  local title=""
  if command -v jq >/dev/null 2>&1; then
    title="$(curl -sf --max-time 15 "${stats_url}" 2>/dev/null | jq -r --arg m "${mount}" '.icestats.source | if type=="array" then .[] else . end | select(.listenurl | contains($m)) | .title // ""' 2>/dev/null | head -n1 | tr -d '\r' || true)"
  elif command -v python3 >/dev/null 2>&1; then
    title="$(curl -sf --max-time 15 "${stats_url}" 2>/dev/null | python3 -c "
import sys, json
try:
    data=json.load(sys.stdin)
    src=data['icestats']['source']
    if not isinstance(src,list): src=[src]
    mount=sys.argv[1]
    for s in src:
        if mount in s.get('listenurl',''):
            print(s.get('title',s.get('artist',''))); break
except: pass" "${mount}" 2>/dev/null | tr -d '\r' || true)"
  fi
  printf '%s' "${title}"
}

if [ "${RDS_PROG2_ENABLE}" != "true" ]; then
  _log "RDS_PROG2_ENABLE is not true; exiting"
  exit 0
fi

if [ "${RDS_PROG2_SOURCE}" = "metadata" ] && [ -z "${RADIO2_URL}" ]; then
  _log "RDS_PROG2_SOURCE=metadata but RADIO2_URL is empty; exiting"
  exit 0
fi

if [ "${RDS_PROG2_SOURCE}" = "icecast" ] && { [ -z "${RDS_PROG2_ICECAST_STATS_URL}" ] || [ -z "${RDS_PROG2_ICECAST_MOUNT}" ]; }; then
  _log "RDS_PROG2_SOURCE=icecast but ICECAST_STATS_URL or ICECAST_MOUNT is empty; exiting"
  exit 0
fi

if [ "${RDS_PROG2_SOURCE}" = "url" ] && [ -z "${RDS_PROG2_RT_URL}" ]; then
  _log "RDS_PROG2_RT_URL is empty; exiting"
  exit 0
fi

if ! [[ "${RDS_PROG2_INTERVAL_SEC}" =~ ^[0-9]+$ ]] || [ "${RDS_PROG2_INTERVAL_SEC}" -lt 1 ]; then
  RDS_PROG2_INTERVAL_SEC=5
fi

mkdir -p "$(dirname "${RDS_PROG2_RT_PATH}")"
touch "${RDS_PROG2_RT_PATH}" 2>/dev/null || true
tmp_path="${RDS_PROG2_RT_PATH}.tmp"
current_rt=""

while true; do
  if [ "${RDS_PROG2_SOURCE}" = "metadata" ]; then
    rt_text="$(_fetch_stream_title "${RADIO2_URL}")"
    if [ -n "${rt_text}" ]; then
      printf '%s\n' "${rt_text}" > "${tmp_path}"
      mv -f "${tmp_path}" "${RDS_PROG2_RT_PATH}"
    else
      _log "No StreamTitle metadata found from RADIO2_URL"
      rt_text=""
    fi
  elif [ "${RDS_PROG2_SOURCE}" = "icecast" ]; then
    rt_text="$(_fetch_icecast_title "${RDS_PROG2_ICECAST_STATS_URL}" "${RDS_PROG2_ICECAST_MOUNT}")"
    if [ -n "${rt_text}" ]; then
      printf '%s\n' "${rt_text}" > "${tmp_path}"
      mv -f "${tmp_path}" "${RDS_PROG2_RT_PATH}"
    else
      _log "No title from Icecast stats at ${RDS_PROG2_ICECAST_STATS_URL} mount ${RDS_PROG2_ICECAST_MOUNT}"
      rt_text=""
    fi
  else
    if wget -q -T 20 -O "${tmp_path}" "${RDS_PROG2_RT_URL}"; then
      if [ -s "${tmp_path}" ] && grep -q '[^[:space:]]' "${tmp_path}" 2>/dev/null; then
        mv -f "${tmp_path}" "${RDS_PROG2_RT_PATH}"
        rt_text="$(head -n1 "${RDS_PROG2_RT_PATH}" 2>/dev/null || true)"
      else
        rm -f "${tmp_path}" || true
        _log "Fetched empty RT from ${RDS_PROG2_RT_URL}; keeping previous file contents"
        rt_text=""
      fi
    else
      _log "Failed to fetch ${RDS_PROG2_RT_URL}"
      rt_text=""
    fi
  fi

  if [ -n "${rt_text}" ]; then
    current_rt="${rt_text}"
  elif [ -z "${current_rt}" ] && [ -s "${RDS_PROG2_RT_PATH}" ]; then
    current_rt="$(head -n1 "${RDS_PROG2_RT_PATH}" 2>/dev/null || true)"
  fi

  load_override
  [ -n "${OV_PS}" ] && RDS_PROG2_PS="${OV_PS:0:8}"
  if [ -n "${OV_PI}" ] && [[ "${OV_PI}" =~ ^[0-9A-F]{4}$ ]]; then RDS_PROG2_PI="${OV_PI}"; fi
  if [ -n "${OV_PTY}" ] && [[ "${OV_PTY}" =~ ^[0-9]+$ ]] && [ "${OV_PTY}" -ge 0 ] && [ "${OV_PTY}" -le 31 ]; then RDS_PROG2_PTY="${OV_PTY}"; fi
  [ "${OV_TP}" = "true" ] && RDS_PROG2_TP="true"
  [ "${OV_TP}" = "false" ] && RDS_PROG2_TP="false"
  [ "${OV_TA}" = "true" ] && RDS_PROG2_TA="true"
  [ "${OV_TA}" = "false" ] && RDS_PROG2_TA="false"
  [ "${OV_MS}" = "true" ] && RDS_PROG2_MS="true"
  [ "${OV_MS}" = "false" ] && RDS_PROG2_MS="false"
  [ "${OV_CT_ENABLE}" = "true" ] && RDS_PROG2_CT_ENABLE="true"
  [ "${OV_CT_ENABLE}" = "false" ] && RDS_PROG2_CT_ENABLE="false"
  [ "${OV_CT_MODE}" = "utc" ] && RDS_PROG2_CT_MODE="utc"
  [ "${OV_CT_MODE}" = "local" ] && RDS_PROG2_CT_MODE="local"
  if [ -n "${OV_RT}" ]; then
    current_rt="${OV_RT}"
    printf '%s\n' "${current_rt}" > "${tmp_path}"
    mv -f "${tmp_path}" "${RDS_PROG2_RT_PATH}"
  fi

  write_rds_info "${current_rt}"

  sleep "${RDS_PROG2_INTERVAL_SEC}"
done
RDS2
chown "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}/rds-sync-prog2.sh"
chmod 750 "${SYS_SCRIPTS_DIR}/rds-sync-prog2.sh"
echo "[SUCCESS] Created ${SYS_SCRIPTS_DIR}/rds-sync-prog2.sh"

cat > "${RDS_SYNC_PROG2_SERVICE}" <<EOF
[Unit]
Description=oMPX Program 2 RDS text sync
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${OMPX_USER}
Group=${OMPX_USER}
WorkingDirectory=${OMPX_HOME}
Environment=HOME=${OMPX_HOME}
ExecStart=${SYS_SCRIPTS_DIR}/rds-sync-prog2.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "${RDS_SYNC_PROG2_SERVICE}"
chown root:root "${RDS_SYNC_PROG2_SERVICE}"
echo "[SUCCESS] Installed rds-sync-prog2.service"

# --- Startup integration ---
if has_systemd; then
echo "[INFO] Enabling and starting systemd services..."
systemctl daemon-reload || true
echo "[INFO] Enabling mpx-processing-alsa.service..."
systemctl enable --now mpx-processing-alsa.service || true
if [ "${ICECAST_MODE}" != "disabled" ]; then
  echo "[INFO] Enabling mpx-mix.service (Icecast mode: ${ICECAST_MODE})..."
  systemctl enable --now mpx-mix.service || true
else
  echo "[INFO] Icecast mode is 'disabled'; mpx-mix.service installed but NOT started"
  echo "[INFO] To enable later: edit /home/ompx/.profile, set ICECAST_MODE, then: systemctl enable --now mpx-mix.service"
  systemctl enable mpx-mix.service || true
fi
echo "[INFO] Enabling mpx-watchdog.service..."
systemctl enable --now mpx-watchdog.service || true
echo "[INFO] Enabling source ingest services..."
systemctl enable --now mpx-source1.service || true
if [ "${PROGRAM2_ENABLED}" = "true" ]; then
  systemctl enable --now mpx-source2.service || true
else
  echo "[INFO] PROGRAM2_ENABLED=false; leaving mpx-source2.service disabled"
  systemctl disable --now mpx-source2.service 2>/dev/null || true
fi
echo "[INFO] Enabling mpx-stream-pull.service..."
systemctl enable --now mpx-stream-pull.service || true
if [ "${RDS_PROG1_ENABLE}" = "true" ]; then
  echo "[INFO] Enabling rds-sync-prog1.service..."
  systemctl enable --now rds-sync-prog1.service || true
else
  echo "[INFO] Program 1 RDS sync disabled; installing service but not starting it"
  systemctl disable rds-sync-prog1.service >/dev/null 2>&1 || true
fi
if [ "${RDS_PROG2_ENABLE}" = "true" ]; then
  echo "[INFO] Enabling rds-sync-prog2.service..."
  systemctl enable --now rds-sync-prog2.service || true
else
  echo "[INFO] Program 2 RDS sync disabled; installing service but not starting it"
  systemctl disable rds-sync-prog2.service >/dev/null 2>&1 || true
fi
if [ "${OMPX_WEB_UI_ENABLE}" = "true" ]; then
  echo "[INFO] Enabling ompx-web-ui.service..."
  systemctl enable --now ompx-web-ui.service || true
else
  echo "[INFO] oMPX web UI disabled; leaving ompx-web-ui.service stopped"
  systemctl disable --now ompx-web-ui.service >/dev/null 2>&1 || true
fi
if [ "${OMPX_WEB_KIOSK_ENABLE}" = "true" ] && [ "${OMPX_WEB_UI_ENABLE}" = "true" ]; then
  echo "[INFO] Enabling ompx-web-kiosk.service..."
  systemctl enable --now ompx-web-kiosk.service || true
else
  echo "[INFO] oMPX web kiosk disabled; leaving ompx-web-kiosk.service stopped"
  systemctl disable --now ompx-web-kiosk.service >/dev/null 2>&1 || true
fi
if [ "${ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE}" = true ]; then
  if [ "${START_STEREO_TOOL_AFTER_INSTALL}" = true ]; then
    echo "[INFO] Enabling and starting stereo-tool-enterprise.service..."
    systemctl enable --now stereo-tool-enterprise.service || true
  else
    echo "[INFO] Enabling stereo-tool-enterprise.service for next boot (not starting now)..."
    systemctl enable stereo-tool-enterprise.service || true
  fi
fi

# Remove old cron boot starter if present to avoid duplicate starts on systemd hosts.
if have_crontab && id -u "${OMPX_USER}" >/dev/null 2>&1; then
  crontab -u "${OMPX_USER}" -l 2>/dev/null | grep -v "${SYS_SCRIPTS_DIR}/start_or_shell.sh --start" | sed '/^$/d' | crontab -u "${OMPX_USER}" - 2>/dev/null || true
fi
else
echo "[INFO] systemd not detected; configuring cron @reboot stream startup fallback"
CRON_LINE1="@reboot sleep ${CRON_SLEEP} && ${SYS_SCRIPTS_DIR}/start_or_shell.sh --start >>${OMPX_LOG_DIR}/radio-source-start.log 2>&1 &"
if have_crontab; then
existing=$(crontab -u "${OMPX_USER}" -l 2>/dev/null || true)
new_cron="${existing}"
echo "$existing" | grep -F -q "${SYS_SCRIPTS_DIR}/source1.sh" >/dev/null 2>&1 || new_cron="${new_cron}
${CRON_LINE1}"
printf "%s\n" "${new_cron}" | sed '/^$/d' | crontab -u "${OMPX_USER}" -
echo "[SUCCESS] Cron fallback configured for ${OMPX_USER}"
else
echo "[WARNING] crontab command not found; no automatic stream startup is configured"
fi
if [ "${ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE}" = true ] && [ "${START_STEREO_TOOL_AFTER_INSTALL}" = true ] && [ -x "${STEREO_TOOL_ENTERPRISE_LAUNCHER}" ]; then
  echo "[INFO] Starting Stereo Tool Enterprise immediately (non-systemd fallback)..."
  runuser -u "${OMPX_USER}" -- nohup "${STEREO_TOOL_ENTERPRISE_LAUNCHER}" >/dev/null 2>&1 &
fi
if [ "${OMPX_WEB_UI_ENABLE}" = "true" ] && [ -x "${SYS_SCRIPTS_DIR}/ompx-web-ui.py" ]; then
  echo "[INFO] Starting oMPX web UI immediately (non-systemd fallback)..."
  runuser -u "${OMPX_USER}" -- nohup /usr/bin/python3 "${SYS_SCRIPTS_DIR}/ompx-web-ui.py" >/dev/null 2>&1 &
fi
if [ "${OMPX_WEB_KIOSK_ENABLE}" = "true" ] && [ -x "${SYS_SCRIPTS_DIR}/ompx-web-kiosk.sh" ]; then
  echo "[INFO] Starting oMPX web kiosk immediately (non-systemd fallback)..."
  runuser -u "${OMPX_USER}" -- nohup "${SYS_SCRIPTS_DIR}/ompx-web-kiosk.sh" >/dev/null 2>&1 &
fi
fi
_log "Install complete. Profile: ${PROFILE}"
echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║                    INSTALLATION COMPLETE!                              ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Configure radio streams:"
echo "     ${OMPX_ADD} --radio 1 --url 'https://your.stream/url' --cron-user oMPX --start-now"
echo "     ${OMPX_ADD} --radio 2 --url 'https://your.stream/url' --cron-user oMPX --start-now"
echo "     Broadcast delay is optional and applied at ingest."
echo "     Defaults: INGEST_DELAY_SEC=${INGEST_DELAY_SEC}, P1_INGEST_DELAY_SEC=${P1_INGEST_DELAY_SEC:-${INGEST_DELAY_SEC}}, P2_INGEST_DELAY_SEC=${P2_INGEST_DELAY_SEC:-${INGEST_DELAY_SEC}}"
echo "     Set delay to 0 to disable it per channel."
if [ "${PROGRAM2_ENABLED}" = "true" ]; then
  echo "     After changing it, restart ingest: systemctl restart mpx-source1.service mpx-source2.service"
else
  echo "     After changing it, restart ingest: systemctl restart mpx-source1.service"
  echo "     Program 2 is disabled by default. To enable: set PROGRAM2_ENABLED=true, configure RADIO2_URL, rerun installer to provision P2 ALSA sinks/cards, then enable mpx-source2.service."
fi
echo ""
echo "  2. Check service status:"
if has_systemd; then
  echo "     systemctl status mpx-processing-alsa.service"
  echo "     systemctl status mpx-watchdog.service"
  echo "     systemctl status mpx-stream-pull.service"
  echo "     systemctl status rds-sync-prog1.service"
  echo "     systemctl status rds-sync-prog2.service"
  echo "     systemctl status stereo-tool-enterprise.service"
  echo "     systemctl status ompx-web-ui.service"
  echo "     systemctl status ompx-web-kiosk.service"
else
  echo "     crontab -u ${OMPX_USER} -l"
fi
echo ""
echo "  3. View logs:"
echo "     journalctl -u mpx-processing-alsa.service -f"
echo "     journalctl -u rds-sync-prog1.service -f"
echo "     journalctl -u rds-sync-prog2.service -f"
echo "     tail -f ${OMPX_LOG_DIR}/radio-source1.log"
echo "     tail -f ${OMPX_LOG_DIR}/radio-source2.log"
echo ""
echo "  4. Verify ALSA named sinks:"
playback_pattern='ompx_prg1in|ompx_prg1mpx|ompx_mpx_to_icecast'
capture_pattern='ompx_prg1in_cap|ompx_prg1mpx_cap'
if [ "${PROGRAM2_ENABLED}" = "true" ]; then
  playback_pattern="${playback_pattern}|ompx_prg2in|ompx_prg2mpx"
  capture_pattern="${capture_pattern}|ompx_prg2in_cap|ompx_prg2mpx_cap"
fi
if [ "${ENABLE_PREVIEW_SINKS}" = "true" ]; then
  playback_pattern="${playback_pattern}|ompx_prg1prev"
  capture_pattern="${capture_pattern}|ompx_prg1prev_cap"
  if [ "${PROGRAM2_ENABLED}" = "true" ]; then
    playback_pattern="${playback_pattern}|ompx_prg2prev"
    capture_pattern="${capture_pattern}|ompx_prg2prev_cap"
  fi
fi
if [ "${ENABLE_DSCA_SINKS}" = "true" ]; then
  playback_pattern="${playback_pattern}|ompx_dsca_src|ompx_dsca_injection"
  capture_pattern="${capture_pattern}|ompx_dsca_src_cap"
fi
echo "     aplay -L | grep -E '${playback_pattern}'"
echo "     arecord -L | grep -E '${capture_pattern}'"
echo ""
echo "  5. Runtime endpoint logs:"
echo "     source*.sh logs print the chosen ALSA write/playback endpoint"
echo "     mpx-processing-alsa.service logs print the chosen capture endpoints"
echo ""
echo "  6. Print resolved sink-to-hardware map:"
echo "     sudo ${ASOUND_MAP_HELPER}"
echo ""
echo "  7. Access oMPX user shell:"
echo "     sudo su - ompx"
echo ""
echo "  8. Stereo Tool Enterprise web UI (if enabled):"
echo "     http://<this-host>:${STEREO_TOOL_WEB_PORT}/"
echo "     Bind: ${STEREO_TOOL_WEB_BIND}  Whitelist: ${STEREO_TOOL_WEB_WHITELIST}"
echo ""
echo "  9. RDS/RadioText file paths for your processor:"
echo "     Program 1 RT file: /home/ompx/rds/prog1/rt.txt"
echo "     Program 2 RT file: /home/ompx/rds/prog2/rt.txt"
echo "     Program 1 RDS sidecar JSON: /home/ompx/rds/prog1/rds-info.json"
echo "     Program 2 RDS sidecar JSON: /home/ompx/rds/prog2/rds-info.json"
echo "     Sidecar fields: ps, pi, pty, tp, ta, ms, ct, rt"
echo "     RDS source modes per program:"
echo "       U (url)      - wget a plain-text URL each interval"
echo "       M (metadata) - extract StreamTitle from stream audio (ICY; works with MP3/AAC)"
echo "       I (icecast)  - query Icecast stats JSON API (works with any codec including Opus)"
echo "     Icecast stats mode example (for http://host:8010/transmitter):"
echo "       Stats URL:  http://host:8010/status-json.xsl"
echo "       Mount:      /transmitter"
echo "     Stereo Tool example strings:"
echo "       Program 1: \\r\"/home/ompx/rds/prog1/rt.txt\""
echo "       Program 2: \\r\"/home/ompx/rds/prog2/rt.txt\""
echo "     Note: this installer uses 'prog1' and 'prog2' in the directory names."
echo ""
echo "  10. oMPX web UI (live patch preview + waveform/spectrum):"
echo "      http://<this-host>:${OMPX_WEB_PORT}/"
echo "      Bind: ${OMPX_WEB_BIND}  Whitelist: ${OMPX_WEB_WHITELIST}"
echo "      Auth: ${OMPX_WEB_AUTH_ENABLE}  User: ${OMPX_WEB_AUTH_USER}"
if [ "${OMPX_WEB_AUTH_ENABLE}" = "true" ]; then
  echo "      Password: ${OMPX_WEB_AUTH_PASSWORD}"
fi
echo "      Kiosk: ${OMPX_WEB_KIOSK_ENABLE}  Display: ${OMPX_WEB_KIOSK_DISPLAY}"
echo "      Kiosk URL: ${OMPX_WEB_KIOSK_URL}"
echo ""
echo "  11. Multiband module profile selection (optional processing path):"
echo "      MODULES_DIR=${MODULES_DIR}"
echo "      MULTIBAND_PROFILE=${MULTIBAND_PROFILE}"
echo "      Example command:"
echo "      \"${MODULES_DIR}/multiband_agc.sh\" --profile \"${MULTIBAND_PROFILE}\" --input-url ompx_prg1in_cap --output-url ompx_prg1in --sample-rate ${SAMPLE_RATE}"
echo ""
echo "  12. Stereo Tool replacement wrapper backend:"
echo "      OMPX_STEREO_BACKEND=${OMPX_STEREO_BACKEND}"
echo "      OMPX_WRAPPER_RDS_ENABLE=${OMPX_WRAPPER_RDS_ENABLE}"
echo "      OMPX_WRAPPER_SAMPLE_RATE=${OMPX_WRAPPER_SAMPLE_RATE}"
echo "      OMPX_WRAPPER_PILOT_LEVEL=${OMPX_WRAPPER_PILOT_LEVEL}"
echo "      OMPX_WRAPPER_RDS_LEVEL=${OMPX_WRAPPER_RDS_LEVEL}"
echo "      OMPX_WRAPPER_PRESET=${OMPX_WRAPPER_PRESET}"
echo "      OMPX_FM_PREEMPHASIS=${OMPX_FM_PREEMPHASIS}"
if [ -n "${OMPX_WRAPPER_RDS_ENCODER_CMD}" ]; then
  echo "      OMPX_WRAPPER_RDS_ENCODER_CMD is set"
else
  echo "      OMPX_WRAPPER_RDS_ENCODER_CMD is empty (RDS hook uses silence)"
fi
echo "      Backends: stereotool | ompx-mpx | passthrough"
echo ""

if [ "$CONFIG_SKIP" = false ]; then
echo "Apply ALSA settings now?"
echo "  A) Apply now (no reboot)"
echo "  R) Reboot now and apply"
echo "  W) Wait for next reboot"
echo "  M) Manual apply later"
read -t 45 -p "Select [A/R/W/M] (default A): " apply_choice || true
apply_choice="${apply_choice:-A}"
apply_choice=${apply_choice^^}
case "$apply_choice" in
  A)
    if [ "$CONFIG_OVERWRITE" = false ] && [ -x "${ASOUND_SWITCH_HELPER}"; then
      echo "[INFO] Promoting staged test profile with ${ASOUND_SWITCH_HELPER}..."
      "${ASOUND_SWITCH_HELPER}" || true
    fi
    echo "[INFO] Restarting oMPX runtime to apply changes..."
    if has_systemd; then
      systemctl restart mpx-stream-pull.service mpx-processing-alsa.service mpx-watchdog.service 2>/dev/null || true
    else
      "${SYS_SCRIPTS_DIR}/start_or_shell.sh" --start || true
    fi
    echo "[SUCCESS] Applied runtime settings without reboot"
    ;;
  R)
    echo "[INFO] Reboot requested by user"
    reboot
    ;;
  W)
    echo "[INFO] Keeping settings for next reboot"
    ;;
  M)
    echo "[INFO] Manual apply selected"
    echo "[INFO] To apply later: sudo ${ASOUND_SWITCH_HELPER}"
    ;;
  *)
    echo "[WARNING] Invalid choice; no reboot performed."
    echo "[INFO] Apply later with: sudo ${ASOUND_SWITCH_HELPER}"
    ;;
esac
echo ""
fi

chmod +x "$0" || true
echo "[SUCCESS] Installation finished successfully!"
exit 0
