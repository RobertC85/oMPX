#!/usr/bin/env bash
set -euo pipefail
# oMPX unified installer + ALSA asound.conf setup (192kHz sample rate, 80kHz subcarrier frequency)
# Requires: Debian/Ubuntu or bare metal with standard kernel (not Proxmox PVE, and yes we know Proxmox is based on Debian, but their custom kernel often lacks snd_aloop which is critical for this setup)
# For best results, use a standard Debian kernel (linux-image-amd64) that includes snd_aloop
# Date: 2026-04-07

echo "[$(date +'%F %T')] oMPX installer starting..."
# --- Configurable variables ---
ENV_RADIO1_SET="${RADIO1_URL+x}"
ENV_RADIO1_VAL="${RADIO1_URL-}"
ENV_RADIO2_SET="${RADIO2_URL+x}"
ENV_RADIO2_VAL="${RADIO2_URL-}"
ENV_STREAM_ENGINE_SET="${STREAM_ENGINE+x}"
ENV_STREAM_ENGINE_VAL="${STREAM_ENGINE-}"
ENV_STREAM_SILENCE_SET="${STREAM_SILENCE_MAX_DBFS+x}"
ENV_STREAM_SILENCE_VAL="${STREAM_SILENCE_MAX_DBFS-}"

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
OMPX_ADD="/usr/local/bin/ompx_add_source"
ASOUND_CONF_PATH="/etc/asound.conf"
OMPX_AUDIO_UDEV_RULE="/etc/udev/rules.d/70-ompx-audio.rules"
ASOUND_MAP_HELPER="/usr/local/bin/asound-map"
ASOUND_SWITCH_HELPER="/usr/local/bin/asound-switch"
SAMPLE_RATE=192000
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
ALLOW_PLACEHOLDER_STREAM_OVERWRITE="${ALLOW_PLACEHOLDER_STREAM_OVERWRITE:-false}"
REMOVE_OLD_SINKS="${REMOVE_OLD_SINKS:-false}"
RUN_QUICK_AUDIO_TEST="${RUN_QUICK_AUDIO_TEST:-false}"
STREAM_VALIDATION_ENABLED="${STREAM_VALIDATION_ENABLED:-false}"
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

# Icecast output (MPX mix → Icecast)
ICECAST_HOST="${ICECAST_HOST:-127.0.0.1}"
ICECAST_PORT="${ICECAST_PORT:-8000}"
ICECAST_SOURCE_USER="${ICECAST_SOURCE_USER:-source}"
ICECAST_PASSWORD="${ICECAST_PASSWORD:-hackme}"
ICECAST_ADMIN_USER="${ICECAST_ADMIN_USER:-admin}"
ICECAST_MOUNT="${ICECAST_MOUNT:-/mpx.flac}"
ICECAST_SAMPLE_RATE="${ICECAST_SAMPLE_RATE:-192000}"
ICECAST_CODEC="flac"
# ICECAST_MODE: local | remote | disabled
ICECAST_MODE="${ICECAST_MODE:-disabled}"
# ALSA capture endpoints Stereo Tool Enterprise writes its processed output to
ST_OUT_P1="${ST_OUT_P1:-ompx_prg1mpx_cap}"
ST_OUT_P2="${ST_OUT_P2:-ompx_prg2mpx_cap}"
RDS_PROG1_ENABLE="${RDS_PROG1_ENABLE:-false}"
RDS_PROG1_SOURCE="${RDS_PROG1_SOURCE:-url}"
RDS_PROG1_RT_URL="${RDS_PROG1_RT_URL:-}"
RDS_PROG1_INTERVAL_SEC="${RDS_PROG1_INTERVAL_SEC:-5}"
RDS_PROG1_RT_PATH="${RDS_PROG1_RT_PATH:-${OMPX_HOME}/rds/prog1/rt.txt}"
RDS_PROG2_ENABLE="${RDS_PROG2_ENABLE:-false}"
RDS_PROG2_SOURCE="${RDS_PROG2_SOURCE:-url}"
RDS_PROG2_RT_URL="${RDS_PROG2_RT_URL:-}"
RDS_PROG2_INTERVAL_SEC="${RDS_PROG2_INTERVAL_SEC:-5}"
RDS_PROG2_RT_PATH="${RDS_PROG2_RT_PATH:-${OMPX_HOME}/rds/prog2/rt.txt}"
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

  cat > "${OMPX_AUDIO_UDEV_RULE}" <<'UDEVRULE'
SUBSYSTEM=="sound", GROUP="audio", MODE="0660"
UDEVRULE
  chmod 644 "${OMPX_AUDIO_UDEV_RULE}" || true

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

# Debug: Check ALSA visibility
{
  echo "stereo-tool-enterprise-launch: ALSA diagnostics"
  echo "  User: \$(whoami)"
  echo "  Groups: \$(id -nG)"
  echo "  /dev/snd permissions: \$(ls -ld /dev/snd 2>/dev/null || echo 'N/A')"
  echo "  /dev/snd contents: \$(ls -la /dev/snd 2>/dev/null | wc -l) items"
  echo "  aplay -l output:"
  aplay -l 2>&1 | head -10 || true
  echo "  aplay -L output (friendly names):"
  aplay -L 2>&1 | head -10 || true
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
  echo ""
  echo "=== Icecast output configuration ==="
  echo "  L) Local  — install Icecast2 on THIS machine; downstream clients pull from here"
  echo "  R) Remote — push encoded stream to a remote Icecast server (transmitter or third-party)"
  echo "  S) Skip   — configure Icecast later; mpx-mix service will remain disabled"
  read -t 60 -p "Choose Icecast mode [L/R/S] (default S): " _ice_mode || _ice_mode="S"
  _ice_mode=${_ice_mode^^}

  case "${_ice_mode}" in
    L)
      ICECAST_MODE="local"
      ICECAST_HOST="127.0.0.1"
      read -t 60 -p "Icecast HTTP port (default 8000): " _ice_port || _ice_port=""
      [[ "${_ice_port}" =~ ^[0-9]+$ ]] && ICECAST_PORT="${_ice_port}" || ICECAST_PORT=8000
      read -t 60 -p "Icecast source username (default source): " _ice_source_user || _ice_source_user=""
      ICECAST_SOURCE_USER="${_ice_source_user:-source}"
      read -t 60 -p "Icecast source password (default hackme): " _ice_pass || _ice_pass=""
      ICECAST_PASSWORD="${_ice_pass:-hackme}"
      read -t 60 -p "Mount point (default /mpx.flac): " _ice_mount || _ice_mount=""
      _ice_mount="${_ice_mount:-mpx.flac}"; ICECAST_MOUNT="/${_ice_mount#/}"
      read -t 60 -p "Icecast admin username (default admin): " _ice_admin_user || _ice_admin_user=""
      ICECAST_ADMIN_USER="${_ice_admin_user:-admin}"
      read -t 60 -p "Icecast admin password (default admin): " _ice_admin || _ice_admin=""
      _ICE_ADMIN_PASS="${_ice_admin:-admin}"
      read -t 60 -p "Max simultaneous listeners (default 25): " _ice_clients || _ice_clients=""
      [[ "${_ice_clients}" =~ ^[0-9]+$ ]] && _ICE_MAX_LISTENERS="${_ice_clients}" || _ICE_MAX_LISTENERS=25
      read -t 60 -p "Station name shown to listeners (default oMPX): " _ice_name || _ice_name=""
      _ICE_STATION="${_ice_name:-oMPX}"
      echo "[INFO] Local Icecast2 → localhost:${ICECAST_PORT}${ICECAST_MOUNT}"
      ;;
    R)
      ICECAST_MODE="remote"
      read -t 120 -p "Remote Icecast hostname or IP: " _ice_host || _ice_host=""
      if [ -z "${_ice_host}" ]; then
        echo "[WARNING] No host entered — Icecast mode set to disabled"; ICECAST_MODE="disabled"; return
      fi
      ICECAST_HOST="${_ice_host}"
      read -t 60 -p "Remote Icecast port (default 8000): " _ice_port || _ice_port=""
      [[ "${_ice_port}" =~ ^[0-9]+$ ]] && ICECAST_PORT="${_ice_port}" || ICECAST_PORT=8000
      read -t 60 -p "Source username (default source): " _ice_source_user || _ice_source_user=""
      ICECAST_SOURCE_USER="${_ice_source_user:-source}"
      read -t 60 -p "Source password: " _ice_pass || _ice_pass=""
      if [ -z "${_ice_pass}" ]; then
        echo "[WARNING] No password entered — Icecast mode set to disabled"; ICECAST_MODE="disabled"; return
      fi
      ICECAST_PASSWORD="${_ice_pass}"
      read -t 60 -p "Mount point (default /mpx.flac): " _ice_mount || _ice_mount=""
      _ice_mount="${_ice_mount:-mpx.flac}"; ICECAST_MOUNT="/${_ice_mount#/}"
      echo "[INFO] Remote Icecast push → ${ICECAST_HOST}:${ICECAST_PORT}${ICECAST_MOUNT}"
      ;;
    *)
      ICECAST_MODE="disabled"
      echo "[INFO] Icecast skipped — edit /home/ompx/.profile and restart mpx-mix.service later"
      return
      ;;
  esac

  read -t 60 -p "Output sample rate Hz (default 192000, use 48000 for standard): " _ice_sr || _ice_sr=""
  [[ "${_ice_sr}" =~ ^[0-9]+$ ]] && ICECAST_SAMPLE_RATE="${_ice_sr}" || ICECAST_SAMPLE_RATE=192000
  echo "[INFO] Icecast encoder sample rate: ${ICECAST_SAMPLE_RATE} Hz"
  ICECAST_CODEC="flac"
  if [ -z "${ICECAST_MOUNT:-}" ] || [ "${ICECAST_MOUNT}" = "/mpx.ogg" ]; then
    ICECAST_MOUNT="/mpx.flac"
  fi
  echo "[INFO] Icecast codec fixed to FLAC (${ICECAST_MOUNT})"

  echo ""
  echo "MPX capture endpoints consumed by mpx-mix (read/capture side of ST's MPX output loopbacks):"
  read -t 60 -p "Program 1 MPX capture device (default ompx_prg1mpx_cap): " _st_p1 || _st_p1=""
  ST_OUT_P1="${_st_p1:-ompx_prg1mpx_cap}"
  read -t 60 -p "Program 2 MPX capture device (default ompx_prg2mpx_cap, 'none' to disable): " _st_p2 || _st_p2=""
  [ "${_st_p2,,}" = "none" ] && ST_OUT_P2="" || ST_OUT_P2="${_st_p2:-ompx_prg2mpx_cap}"
}

configure_rds_dialog(){
  local _rds_mode_default="U"
  local _rds2_mode_default="U"
  echo ""
  echo "=== RDS sync configuration ==="
  echo "  Syncs RadioText from a text URL OR from stream metadata"
  echo "  Program 1 output file: ${OMPX_HOME}/rds/prog1/rt.txt"
  read -t 60 -p "Enable Program 1 RDS text sync? [y/N] (default N): " _rds_enable || _rds_enable="N"
  _rds_enable=${_rds_enable^^}
  if [ "${_rds_enable}" != "Y" ]; then
    RDS_PROG1_ENABLE="false"
    RDS_PROG1_SOURCE="url"
    RDS_PROG1_RT_URL=""
    echo "[INFO] Program 1 RDS sync disabled"
  else
    RDS_PROG1_ENABLE="true"
    [ "${RDS_PROG1_SOURCE}" = "metadata" ] && _rds_mode_default="M"
    read -t 60 -p "Program 1 RDS source [U=url/M=metadata] (default ${_rds_mode_default}): " _rds_mode || _rds_mode="${_rds_mode_default}"
    _rds_mode=${_rds_mode^^}
    if [ "${_rds_mode}" = "M" ]; then
      RDS_PROG1_SOURCE="metadata"
      RDS_PROG1_RT_URL=""
      if is_placeholder_stream_url "${RADIO1_URL}"; then
        echo "[WARNING] Program 1 stream URL is placeholder/empty; metadata sync may fail until RADIO1_URL is set"
      fi
      echo "[INFO] Program 1 metadata mode enabled (reads StreamTitle from RADIO1_URL)"
    else
      RDS_PROG1_SOURCE="url"
      read -t 180 -p "RDS text URL for Program 1: " _rds_url || _rds_url=""
      if [ -z "${_rds_url}" ]; then
        echo "[WARNING] Empty RDS URL; disabling Program 1 RDS sync"
        RDS_PROG1_ENABLE="false"
        RDS_PROG1_RT_URL=""
      else
        RDS_PROG1_RT_URL="${_rds_url}"
      fi
    fi

    if [ "${RDS_PROG1_ENABLE}" = "true" ]; then
      read -t 60 -p "Refresh interval seconds (default ${RDS_PROG1_INTERVAL_SEC}): " _rds_int || _rds_int=""
      if [[ "${_rds_int}" =~ ^[0-9]+$ ]] && [ "${_rds_int}" -ge 1 ]; then
        RDS_PROG1_INTERVAL_SEC="${_rds_int}"
      fi

      RDS_PROG1_RT_PATH="${OMPX_HOME}/rds/prog1/rt.txt"
      if [ "${RDS_PROG1_SOURCE}" = "metadata" ]; then
        echo "[INFO] Program 1 RDS sync enabled (metadata): RADIO1_URL -> ${RDS_PROG1_RT_PATH} every ${RDS_PROG1_INTERVAL_SEC}s"
      else
        echo "[INFO] Program 1 RDS sync enabled (url): ${RDS_PROG1_RT_URL} -> ${RDS_PROG1_RT_PATH} every ${RDS_PROG1_INTERVAL_SEC}s"
      fi
    fi
  fi

  echo ""
  echo "  Program 2 output file: ${OMPX_HOME}/rds/prog2/rt.txt"
  read -t 60 -p "Enable Program 2 RDS text sync? [y/N] (default N): " _rds2_enable || _rds2_enable="N"
  _rds2_enable=${_rds2_enable^^}
  if [ "${_rds2_enable}" != "Y" ]; then
    RDS_PROG2_ENABLE="false"
    RDS_PROG2_SOURCE="url"
    RDS_PROG2_RT_URL=""
    echo "[INFO] Program 2 RDS sync disabled"
  else
    RDS_PROG2_ENABLE="true"
    [ "${RDS_PROG2_SOURCE}" = "metadata" ] && _rds2_mode_default="M"
    read -t 60 -p "Program 2 RDS source [U=url/M=metadata] (default ${_rds2_mode_default}): " _rds2_mode || _rds2_mode="${_rds2_mode_default}"
    _rds2_mode=${_rds2_mode^^}
    if [ "${_rds2_mode}" = "M" ]; then
      RDS_PROG2_SOURCE="metadata"
      RDS_PROG2_RT_URL=""
      if is_placeholder_stream_url "${RADIO2_URL}"; then
        echo "[WARNING] Program 2 stream URL is placeholder/empty; metadata sync may fail until RADIO2_URL is set"
      fi
      echo "[INFO] Program 2 metadata mode enabled (reads StreamTitle from RADIO2_URL)"
    else
      RDS_PROG2_SOURCE="url"
      read -t 180 -p "RDS text URL for Program 2: " _rds2_url || _rds2_url=""
      if [ -z "${_rds2_url}" ]; then
        echo "[WARNING] Empty RDS URL; disabling Program 2 RDS sync"
        RDS_PROG2_ENABLE="false"
        RDS_PROG2_RT_URL=""
      else
        RDS_PROG2_RT_URL="${_rds2_url}"
      fi
    fi

    if [ "${RDS_PROG2_ENABLE}" = "true" ]; then
      read -t 60 -p "Refresh interval seconds (default ${RDS_PROG2_INTERVAL_SEC}): " _rds2_int || _rds2_int=""
      if [[ "${_rds2_int}" =~ ^[0-9]+$ ]] && [ "${_rds2_int}" -ge 1 ]; then
        RDS_PROG2_INTERVAL_SEC="${_rds2_int}"
      fi

      RDS_PROG2_RT_PATH="${OMPX_HOME}/rds/prog2/rt.txt"
      if [ "${RDS_PROG2_SOURCE}" = "metadata" ]; then
        echo "[INFO] Program 2 RDS sync enabled (metadata): RADIO2_URL -> ${RDS_PROG2_RT_PATH} every ${RDS_PROG2_INTERVAL_SEC}s"
      else
        echo "[INFO] Program 2 RDS sync enabled (url): ${RDS_PROG2_RT_URL} -> ${RDS_PROG2_RT_PATH} every ${RDS_PROG2_INTERVAL_SEC}s"
      fi
    fi
  fi
}

install_icecast_local(){
  echo "[INFO] Installing icecast2..."
  DEBIAN_FRONTEND=noninteractive apt install -y icecast2 || { echo "[WARNING] icecast2 install failed"; return 1; }
  local admin_pass="${_ICE_ADMIN_PASS:-admin}"
  local source_user="${ICECAST_SOURCE_USER:-source}"
  local source_pass="${ICECAST_PASSWORD:-hackme}"
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
  # card has its own ALSA name (loaded with id=<name>) so we reference by name,
  # which is stable across reboots regardless of card number assignment.
  cat <<EOF
# BEGIN OMPX ALSA BLOCK
# oMPX ALSA virtual PCM map (auto-generated)

pcm.ompx_prg1in {
  type plug
  slave.pcm "hw:program1in,0"
  hint {
    show on
    description "oMPX Program 1 Input (write/playback)"
  }
}

pcm.ompx_prg1in_cap {
  type plug
  slave.pcm "hw:program1in,1"
  hint {
    show on
    description "oMPX Program 1 Input Capture (read/capture)"
  }
}

pcm.ompx_prg2in {
  type plug
  slave.pcm "hw:program2in,0"
  hint {
    show on
    description "oMPX Program 2 Input (write/playback)"
  }
}

pcm.ompx_prg2in_cap {
  type plug
  slave.pcm "hw:program2in,1"
  hint {
    show on
    description "oMPX Program 2 Input Capture (read/capture)"
  }
}

pcm.ompx_prg1prev {
  type plug
  slave.pcm "hw:program1preview,0"
  hint {
    show on
    description "oMPX Program 1 Preview (write/playback)"
  }
}

pcm.ompx_prg1prev_cap {
  type plug
  slave.pcm "hw:program1preview,1"
  hint {
    show on
    description "oMPX Program 1 Preview Capture (read/capture)"
  }
}

pcm.ompx_prg2prev {
  type plug
  slave.pcm "hw:program2preview,0"
  hint {
    show on
    description "oMPX Program 2 Preview (write/playback)"
  }
}

pcm.ompx_prg2prev_cap {
  type plug
  slave.pcm "hw:program2preview,1"
  hint {
    show on
    description "oMPX Program 2 Preview Capture (read/capture)"
  }
}

pcm.ompx_prg1mpx {
  type plug
  slave.pcm "hw:program1mpxsrc,0"
  hint {
    show on
    description "oMPX Program 1 MPX Output"
  }
}

pcm.ompx_prg1mpx_cap {
  type plug
  slave.pcm "hw:program1mpxsrc,1"
  hint {
    show on
    description "oMPX Program 1 MPX Output Capture (read/capture)"
  }
}

pcm.ompx_prg2mpx {
  type plug
  slave.pcm "hw:program2mpxsrc,0"
  hint {
    show on
    description "oMPX Program 2 MPX Output"
  }
}

pcm.ompx_prg2mpx_cap {
  type plug
  slave.pcm "hw:program2mpxsrc,1"
  hint {
    show on
    description "oMPX Program 2 MPX Output Capture (read/capture)"
  }
}

pcm.ompx_dsca_src {
  type plug
  slave.pcm "hw:dscasource,0"
  hint {
    show on
    description "oMPX DSCA Source (write/playback)"
  }
}

pcm.ompx_dsca_src_cap {
  type plug
  slave.pcm "hw:dscasource,1"
  hint {
    show on
    description "oMPX DSCA Source Capture (read/capture)"
  }
}

pcm.ompx_dsca_injection {
  type plug
  slave.pcm "hw:dscainjectionsr,0"
  hint {
    show on
    description "oMPX DSCA Injection"
  }
}

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

pcm.ompx_program2_preview {
  type plug
  slave.pcm "ompx_prg2prev"
  hint {
    show on
    description "oMPX Program 2 Preview (alias)"
  }
}

pcm.ompx_program2_preview_capture {
  type plug
  slave.pcm "ompx_prg2prev_cap"
  hint {
    show on
    description "oMPX Program 2 Preview Capture (alias)"
  }
}

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

# END OMPX ALSA BLOCK

EOF
}

write_profile_file(){
  local old_radio1=""
  local old_radio2=""
  ICECAST_CODEC="flac"
  echo "[INFO] Creating user profile configuration..."
  mkdir -p "${OMPX_HOME}"
  PROFILE="${OMPX_HOME}/.profile"

  if [ -f "${PROFILE}" ]; then
    set +u
    . "${PROFILE}" || true
    set -u
    old_radio1="${RADIO1_URL:-}"
    old_radio2="${RADIO2_URL:-}"
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
ICECAST_MODE="${ICECAST_MODE}"
ICECAST_HOST="${ICECAST_HOST}"
ICECAST_PORT="${ICECAST_PORT}"
ICECAST_SOURCE_USER="${ICECAST_SOURCE_USER}"
ICECAST_PASSWORD="${ICECAST_PASSWORD}"
ICECAST_ADMIN_USER="${ICECAST_ADMIN_USER}"
ICECAST_MOUNT="${ICECAST_MOUNT}"
ICECAST_SAMPLE_RATE="${ICECAST_SAMPLE_RATE}"
ICECAST_CODEC="${ICECAST_CODEC}"
ST_OUT_P1="${ST_OUT_P1}"
ST_OUT_P2="${ST_OUT_P2}"
RDS_PROG1_ENABLE="${RDS_PROG1_ENABLE}"
RDS_PROG1_SOURCE="${RDS_PROG1_SOURCE}"
RDS_PROG1_RT_URL="${RDS_PROG1_RT_URL}"
RDS_PROG1_INTERVAL_SEC="${RDS_PROG1_INTERVAL_SEC}"
RDS_PROG1_RT_PATH="${RDS_PROG1_RT_PATH}"
RDS_PROG2_ENABLE="${RDS_PROG2_ENABLE}"
RDS_PROG2_SOURCE="${RDS_PROG2_SOURCE}"
RDS_PROG2_RT_URL="${RDS_PROG2_RT_URL}"
RDS_PROG2_INTERVAL_SEC="${RDS_PROG2_INTERVAL_SEC}"
RDS_PROG2_RT_PATH="${RDS_PROG2_RT_PATH}"
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
  modprobe snd_aloop enable=1 pcm_substreams=2
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
  echo "Streaming ingest engine is fixed to FFmpeg."
  echo "  Reason: simpler runtime, fewer moving parts, no Liquidsoap dependency."
  echo "[INFO] Ingest can be any decodable format; Icecast output is fixed to FLAC at ${ICECAST_SAMPLE_RATE} Hz."
  STREAM_ENGINE="ffmpeg"
  echo "[INFO] Selected streaming engine: ${STREAM_ENGINE}"

  configure_icecast_dialog
  configure_rds_dialog

  echo ""
  FETCH_STEREO_TOOL_ENTERPRISE=false
  ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE=false
  if [ -x "${STEREO_TOOL_ENTERPRISE_BIN}" ]; then
    echo "[INFO] Existing Stereo Tool Enterprise binary detected at ${STEREO_TOOL_ENTERPRISE_BIN}."
    read -t 45 -p "Enable Stereo Tool Enterprise service at boot with existing binary? [Y/n] (default Y): " cfg_st_enable_existing || cfg_st_enable_existing="Y"
    cfg_st_enable_existing=${cfg_st_enable_existing^^}
    if [ "${cfg_st_enable_existing}" != "N" ]; then
      ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE=true
      prompt_stereo_tool_limit_preset
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
      read -t 45 -p "Start Stereo Tool Enterprise immediately after install (no reboot)? [Y/n] (default Y): " cfg_st_start_now || cfg_st_start_now="Y"
      cfg_st_start_now=${cfg_st_start_now^^}
      if [ "${cfg_st_start_now}" = "N" ]; then
        START_STEREO_TOOL_AFTER_INSTALL=false
      else
        START_STEREO_TOOL_AFTER_INSTALL=true
      fi
    fi
  fi

  echo "[INFO] Quick loopback self-test is disabled by default (historically unreliable on some hosts)."
fi

cat > "${ASOUND_MAP_HELPER}" <<'ASMAP'
#!/usr/bin/env bash
set -euo pipefail
echo "oMPX sink map helper"
echo "--------------------"
echo "Write/playback endpoints (send audio into these):"
for id in ompx_prg1in ompx_prg1prev ompx_prg2in ompx_prg2prev ompx_dsca_src ompx_prg1mpx ompx_prg2mpx ompx_dsca_injection ompx_mpx_to_icecast; do
  printf '  %s\n' "$id"
done
echo "Friendly playback aliases:"
for id in ompx_program1_input ompx_program2_input ompx_program1_preview ompx_program2_preview ompx_program1_mpx_output ompx_program2_mpx_output ompx_dsca_source ompx_dsca_injection ompx_mpx_to_icecast; do
  printf '  %s\n' "$id"
done
echo ""
echo "Read/capture endpoints (read audio back from these):"
for id in ompx_prg1in_cap ompx_prg1prev_cap ompx_prg2in_cap ompx_prg2prev_cap ompx_prg1mpx_cap ompx_prg2mpx_cap ompx_dsca_src_cap; do
  printf '  %s\n' "$id"
done
echo "Friendly capture aliases:"
for id in ompx_program1_input_capture ompx_program2_input_capture ompx_program1_preview_capture ompx_program2_preview_capture ompx_program1_mpx_output_capture ompx_program2_mpx_output_capture ompx_dsca_source_capture; do
  printf '  %s\n' "$id"
done
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
read -t 30 -p "Select [K/R/U/A] (default A): " choice || choice="A"
choice=${choice^^}
echo "[INFO] User selected: $choice"
case "$choice" in
R)
echo "[INFO] Performing full cleanup before reinstall..."
echo "[INFO] Stopping systemd services..."
systemctl stop mpx-processing-alsa.service mpx-watchdog.service mpx-stream-pull.service mpx-source1.service mpx-source2.service rds-sync-prog1.service rds-sync-prog2.service 2>/dev/null || true
systemctl stop stereo-tool-enterprise.service 2>/dev/null || true
echo "[INFO] Disabling systemd services..."
systemctl disable mpx-processing-alsa.service mpx-watchdog.service mpx-stream-pull.service mpx-source1.service mpx-source2.service rds-sync-prog1.service rds-sync-prog2.service 2>/dev/null || true
systemctl disable stereo-tool-enterprise.service 2>/dev/null || true
rm -f "${SYSTEMD_DIR}/mpx-processing-alsa.service" "${SYSTEMD_DIR}/mpx-watchdog.service" "${OMPX_STREAM_PULL_SERVICE}" "${OMPX_SOURCE1_SERVICE}" "${OMPX_SOURCE2_SERVICE}" "${RDS_SYNC_PROG1_SERVICE}" "${RDS_SYNC_PROG2_SERVICE}" "${STEREO_TOOL_ENTERPRISE_SERVICE}" "${STEREO_TOOL_ENTERPRISE_LAUNCHER}"
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
systemctl stop stereo-tool-enterprise.service 2>/dev/null || true
echo "[INFO] Disabling systemd services..."
systemctl disable mpx-processing-alsa.service mpx-watchdog.service mpx-stream-pull.service mpx-source1.service mpx-source2.service rds-sync-prog1.service rds-sync-prog2.service 2>/dev/null || true
systemctl disable stereo-tool-enterprise.service 2>/dev/null || true
rm -f "${SYSTEMD_DIR}/mpx-processing-alsa.service" "${SYSTEMD_DIR}/mpx-watchdog.service" "${OMPX_STREAM_PULL_SERVICE}" "${OMPX_SOURCE1_SERVICE}" "${OMPX_SOURCE2_SERVICE}" "${RDS_SYNC_PROG1_SERVICE}" "${RDS_SYNC_PROG2_SERVICE}" "${STEREO_TOOL_ENTERPRISE_SERVICE}" "${STEREO_TOOL_ENTERPRISE_LAUNCHER}"
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
echo "[INFO] Installing base dependencies (curl, wget, alsa-utils, ffmpeg, sox, ladspa-sdk, swh-plugins, cron)..."
DEBIAN_FRONTEND=noninteractive apt install -y curl wget alsa-utils ffmpeg sox ladspa-sdk swh-plugins cron
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
if has_systemd && [ "${AUTO_ENABLE_STEREO_TOOL_IF_PRESENT}" = "true" ] && [ -x "${STEREO_TOOL_ENTERPRISE_BIN}" ]; then
  if [ "${ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE}" != "true" ]; then
    echo "[INFO] Stereo Tool Enterprise binary detected; auto-enabling boot service (AUTO_ENABLE_STEREO_TOOL_IF_PRESENT=true)"
  fi
  ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE=true
fi

if [ "${ENABLE_STEREO_TOOL_ENTERPRISE_SERVICE}" = true ]; then
  apply_stereo_tool_start_limit_preset
  install_stereo_tool_enterprise_service "${STEREO_TOOL_ENTERPRISE_BIN}" "${STEREO_TOOL_ENTERPRISE_LAUNCHER}" "${STEREO_TOOL_WEB_BIND}" "${STEREO_TOOL_WEB_PORT}" "${STEREO_TOOL_WEB_WHITELIST}" "${STEREO_TOOL_START_LIMIT_INTERVAL_SEC}" "${STEREO_TOOL_START_LIMIT_BURST}"
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
echo "[INFO] Expected named ALSA PCMs: write/playback endpoints ompx_prg1in, ompx_prg2in, ompx_prg1prev, ompx_prg2prev, ompx_prg1mpx, ompx_prg2mpx, ompx_dsca_src, ompx_dsca_injection, ompx_mpx_to_icecast; read/capture endpoints ompx_prg1in_cap, ompx_prg2in_cap, ompx_prg1prev_cap, ompx_prg2prev_cap, ompx_prg1mpx_cap, ompx_prg2mpx_cap, ompx_dsca_src_cap"
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
    sox -n -r ${SAMPLE_RATE} -c 2 -b 16 "${test_tone}" synth 1.8 sine 1000 vol 0.6 >/dev/null 2>&1 || true

    if arecord -D ompx_prg1in_cap -f S16_LE -c 2 -r ${SAMPLE_RATE} -d 2 "${test_wav}" >"${test_capture_log}" 2>&1 & then
      rec_pid=$!
      sleep 0.6

      inject_ok=0
      if [ -s "${test_tone}" ]; then
        if timeout 4 aplay -q -D ompx_prg1in "${test_tone}" >"${test_inject_log}" 2>&1; then
          inject_ok=1
        fi
      fi

      if [ "${inject_ok}" -ne 1 ]; then
        if ffmpeg -hide_banner -loglevel error -f lavfi -i "sine=frequency=1000:sample_rate=${SAMPLE_RATE}:duration=1.8" -ac 2 -f alsa ompx_prg1in >"${test_inject_log}" 2>&1; then
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
cat > "${SYS_SCRIPTS_DIR}/source${n}.sh" <<WRAP
#!/usr/bin/env bash
set -euo pipefail
PROFILE="${OMPX_HOME}/.profile"
[ -f "\$PROFILE" ] && . "\$PROFILE"
RADIO_VAR_NAME="RADIO${n}_URL"
RADIO_URL_VALUE="\${!RADIO_VAR_NAME:-}"
INGEST_DELAY_SEC="\${INGEST_DELAY_SEC:-10}"
if ! [[ "\${INGEST_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  INGEST_DELAY_SEC=10
fi
INGEST_DELAY_MS=$((INGEST_DELAY_SEC * 1000))
if [ "${n}" = "1" ]; then
  SINK_NAME="ompx_prg1in"
else
  SINK_NAME="ompx_prg2in"
fi
if ! aplay -L 2>/dev/null | grep -q "^\${SINK_NAME}$"; then
  if [ "${n}" = "1" ]; then
    SINK_NAME="plughw:${LOOPBACK_CARD_REF},0,0"
  else
    SINK_NAME="plughw:${LOOPBACK_CARD_REF},0,1"
  fi
  echo "[\$(date +'%F %T')] source${n}: named sink unavailable; using fallback \${SINK_NAME}"
fi
echo "[\$(date +'%F %T')] source${n}: using ALSA output endpoint \${SINK_NAME}"
echo "[\$(date +'%F %T')] source${n}: ingest via ffmpeg (input format auto-detected, delay \${INGEST_DELAY_SEC}s)"

if [ -z "\${RADIO_URL_VALUE}" ] || [[ "\${RADIO_URL_VALUE}" == *"example-icecast.local"* ]] || [[ "\${RADIO_URL_VALUE}" == *"your.stream/url"* ]]; then
  echo "[\$(date +'%F %T')] source${n}: RADIO${n}_URL is empty/placeholder; exiting"
  exit 0
fi

while true :
do
  sleep 5
  ffmpeg -nostdin -reconnect 1 -reconnect_streamed 1 -reconnect_at_eof 1 -reconnect_delay_max 5 -thread_queue_size 10240 -i "\${RADIO_URL_VALUE}" \
    -vn -sn -dn \
    -max_delay 5000000 \
    -af "aformat=channel_layouts=stereo,adelay=\${INGEST_DELAY_MS}|\${INGEST_DELAY_MS}" \
    -ar ${SAMPLE_RATE} -ac 2 -f alsa "\${SINK_NAME}" || true
done
WRAP
chown "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}/source${n}.sh"
chmod 750 "${SYS_SCRIPTS_DIR}/source${n}.sh"
echo "[SUCCESS] Created source${n}.sh wrapper"
done
# --- Processing script: run_processing_alsa_liquid.sh ---
echo "[INFO] Creating processing script..."

cat > "${SYS_SCRIPTS_DIR}/run_processing_alsa_liquid.sh" <<'RUNP'
#!/usr/bin/env bash
set -euo pipefail
STEREO_TOOL_CMD="/usr/local/bin/stereo-tool"
SAMPLE_RATE=192000
PROG1_ALSA_IN="${PROG1_ALSA_IN:-ompx_prg1in_cap}"
PROG2_ALSA_IN="${PROG2_ALSA_IN:-ompx_prg2in_cap}"
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
wait_for_alsa_endpoint capture "${PROG2_ALSA_IN}" 60 || true
if ! arecord -L 2>/dev/null | grep -q "^${PROG2_ALSA_IN}$"; then
  PROG2_ALSA_IN="hw:${LOOPBACK_CARD_REF},1,1"
  _log "Fallback capture endpoint for Program 2: ${PROG2_ALSA_IN}"
fi
_log "Using capture endpoints: PROG1_ALSA_IN=${PROG1_ALSA_IN}, PROG2_ALSA_IN=${PROG2_ALSA_IN}"

for p in "$MPX_LEFT_MONO" "$MPX_RIGHT_MONO" "$MPX_LEFT_OUT" "$MPX_RIGHT_OUT" "$MPX_STEREO_FIFO"; do rm -f "$p" || true; mkfifo "$p"; done
ffmpeg -hide_banner -loglevel warning -f alsa -thread_queue_size 10240 -i "${PROG1_ALSA_IN}" -map_channel 0.0.0 -f s16le -ac 1 -ar ${SAMPLE_RATE} - > "${MPX_LEFT_MONO}" &
FF_PROG1_MONO_PID=$!; _log "Spawned PROG1 mono extractor pid $FF_PROG1_MONO_PID"
if arecord -L 2>/dev/null | grep -q "^${PROG2_ALSA_IN}$" || [[ "${PROG2_ALSA_IN}" == hw:Loopback,* ]]; then
ffmpeg -hide_banner -loglevel warning -f alsa -thread_queue_size 10240 -i "${PROG2_ALSA_IN}" -map_channel 0.0.0 -f s16le -ac 1 -ar ${SAMPLE_RATE} - > "${MPX_RIGHT_MONO}" &
FF_PROG2_MONO_PID=$!; _log "Spawned PROG2 mono extractor pid ${FF_PROG2_MONO_PID:-0}"
else
( while :; do dd if=/dev/zero bs=4096 count=256 status=none; sleep 0.1; done ) > "${MPX_RIGHT_MONO}" &
SILENCE_PID=$!
_log "${PROG2_ALSA_IN} not found; injecting silence on right channel"
fi
"${STEREO_TOOL_CMD}" --mode live --left-fifo "${MPX_LEFT_MONO}" --right-fifo "${MPX_RIGHT_MONO}" --out-left-fifo "${MPX_LEFT_OUT}" --out-right-fifo "${MPX_RIGHT_OUT}" &
STEREO_PID=$!; _log "Started stereo-tool wrapper pid ${STEREO_PID}"
ffmpeg -hide_banner -loglevel warning -f s16le -ar ${SAMPLE_RATE} -ac 1 -i "${MPX_LEFT_OUT}" -f s16le -ar ${SAMPLE_RATE} -ac 1 -i "${MPX_RIGHT_OUT}" -filter_complex "[0:a][1:a]join=inputs=2:channel_layout=stereo[aout]" -map "[aout]" -f s16le -ar ${SAMPLE_RATE} -ac 2 - > "${MPX_STEREO_FIFO}" &
FF_MERGE_PID=$!; _log "ffmpeg merge pid $FF_MERGE_PID"
ALSA_OUTPUT="${ALSA_OUTPUT:-}"
if [ -z "$ALSA_OUTPUT" ]; then
if wait_for_alsa_endpoint playback "ompx_prg1in" 20; then
ALSA_OUTPUT="ompx_prg1in"
elif aplay -l 2>/dev/null | grep -qi loopback; then
ALSA_OUTPUT="hw:${LOOPBACK_CARD_REF},0,0"
fi
fi
if [ -z "$ALSA_OUTPUT" ]; then _log "No ALSA output selected."; exit 1; fi
ffmpeg -hide_banner -loglevel warning -f s16le -ar ${SAMPLE_RATE} -ac 2 -i "${MPX_STEREO_FIFO}" -f wav - | aplay -f S16_LE -c 2 -r ${SAMPLE_RATE} -D "${ALSA_OUTPUT}" &
PLAY_PID=$!; _log "MPX playback started (pid ${PLAY_PID:-0})"
wait ${PLAY_PID:-0} || true
kill ${FF_PROG1_MONO_PID:-0} ${FF_PROG2_MONO_PID:-0} ${STEREO_PID:-0} ${FF_MERGE_PID:-0} 2>/dev/null || true
_log "run_processing_alsa_liquid.sh exiting"
RUNP
chown "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}/run_processing_alsa_liquid.sh"
chmod 750 "${SYS_SCRIPTS_DIR}/run_processing_alsa_liquid.sh"
echo "[SUCCESS] Processing script created"

# --- MPX mix + Icecast encoder script ---
echo "[INFO] Creating mpx-mix.sh (mono sum, hard pan, Icecast ffmpeg encoder)..."
cat > "${SYS_SCRIPTS_DIR}/mpx-mix.sh" <<'MPXMIX'
#!/usr/bin/env bash
# mpx-mix.sh — read two Stereo Tool output loopbacks, mono-sum each,
# hard pan P1→L / P2→R, combine to stereo, encode (Opus/FLAC) → Icecast.
set -euo pipefail

PROFILE="/home/ompx/.profile"
[ -f "${PROFILE}" ] && . "${PROFILE}"

ICECAST_HOST="${ICECAST_HOST:-127.0.0.1}"
ICECAST_PORT="${ICECAST_PORT:-8000}"
ICECAST_SOURCE_USER="${ICECAST_SOURCE_USER:-source}"
ICECAST_PASSWORD="${ICECAST_PASSWORD:-hackme}"
ICECAST_MOUNT="${ICECAST_MOUNT:-/mpx.flac}"
ICECAST_SAMPLE_RATE="${ICECAST_SAMPLE_RATE:-192000}"
ICECAST_CODEC="flac"
ICECAST_MODE="${ICECAST_MODE:-disabled}"
ST_OUT_P1="${ST_OUT_P1:-ompx_prg1mpx_cap}"
ST_OUT_P2="${ST_OUT_P2:-ompx_prg2mpx_cap}"
OMPX_LOG_DIR="/home/ompx/logs"

mkdir -p "${OMPX_LOG_DIR}"
_log(){ logger -t mpx-mix "$*"; echo "$(date +'%F %T') [mpx-mix] $*"; }

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

_log "Waiting for ST output endpoints..."
wait_alsa_cap "${ST_OUT_P1}" || { _log "ERROR: ${ST_OUT_P1} not available"; exit 1; }

# Check if P2 is available; fall back to silence if not
P2_AVAILABLE=0
if arecord -L 2>/dev/null | grep -q "^${ST_OUT_P2}$"; then
  P2_AVAILABLE=1
fi

_log "P1 source: ${ST_OUT_P1}"
_log "P2 source: ${ST_OUT_P2} (available: ${P2_AVAILABLE})"
if [ "${ICECAST_MOUNT}" = "/mpx.ogg" ]; then
  ICECAST_MOUNT="/mpx.flac"
fi
_log "Icecast: flac ${ICECAST_SAMPLE_RATE}Hz → icecast://${ICECAST_HOST}:${ICECAST_PORT}${ICECAST_MOUNT}"

CODEC_ARGS=(-c:a flac -compression_level 0 -content_type audio/flac -f flac)

if [ "${P2_AVAILABLE}" -eq 1 ]; then
  # Both programs available: P1 mono → L, P2 mono → R
  # anoisesrc at -80 dBFS (amplitude 0.0001) split to both channels keeps VLC/players
  # alive even when one program carries silence — FLAC all-zero frames cause many
  # players to never activate their audio output.
  exec ffmpeg -nostdin \
    -f alsa -thread_queue_size 16384 -i "${ST_OUT_P1}" \
    -f alsa -thread_queue_size 16384 -i "${ST_OUT_P2}" \
    -filter_complex \
      "anoisesrc=r=${ICECAST_SAMPLE_RATE}:amplitude=0.0001,asplit=2[kpl][kpr];\
       [0:a]pan=mono|c0=0.5*c0+0.5*c1,aresample=${ICECAST_SAMPLE_RATE}[p1raw];\
       [1:a]pan=mono|c0=0.5*c0+0.5*c1,aresample=${ICECAST_SAMPLE_RATE}[p2raw];\
       [p1raw][kpl]amix=inputs=2:normalize=0[p1];\
       [p2raw][kpr]amix=inputs=2:normalize=0[p2];\
       [p1][p2]join=inputs=2:channel_layout=stereo[out]" \
    -map "[out]" \
    -ice_name "oMPX Stereo 192k" \
    -ice_description "P1 (L) + P2 (R) mono-summed, hard-panned" \
    "${CODEC_ARGS[@]}" \
    "icecast://${ICECAST_SOURCE_USER}:${ICECAST_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}${ICECAST_MOUNT}"
else
  # Only P1: duplicate to both channels so clients always receive full L/R program audio.
  _log "P2 not available — duplicating P1 to both channels"
  exec ffmpeg -nostdin \
    -f alsa -thread_queue_size 16384 -i "${ST_OUT_P1}" \
    -filter_complex \
      "anoisesrc=r=${ICECAST_SAMPLE_RATE}:amplitude=0.0001[kp];\
       [0:a]pan=mono|c0=0.5*c0+0.5*c1,aresample=${ICECAST_SAMPLE_RATE}[p1raw];\
       [p1raw][kp]amix=inputs=2:normalize=0[mono];\
       [mono]asplit=2[l][r];\
       [l][r]join=inputs=2:channel_layout=stereo[out]" \
    -map "[out]" \
    -ice_name "oMPX Stereo 192k" \
    -ice_description "P1 duplicated to L+R (P2 not configured)" \
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
ExecStart=${SYS_SCRIPTS_DIR}/run_processing_alsa_liquid.sh
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

cat > "${SYSTEMD_DIR}/mpx-mix.service" <<EOF
[Unit]
Description=oMPX MPX mix — mono sum / hard pan / Icecast FLAC encoder
After=network-online.target stereo-tool-enterprise.service sound.target
Wants=stereo-tool-enterprise.service

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
if /usr/local/bin/stereo-tool.real-check >/dev/null 2>&1; then exec stereo-tool "$@"; fi
LEFT_IN=""; RIGHT_IN=""; LEFT_OUT=""; RIGHT_OUT=""
while [ $# -gt 0 ]; do case "$1" in --left-fifo) LEFT_IN="$2"; shift 2;; --right-fifo) RIGHT_IN="$2"; shift 2;; --out-left-fifo) LEFT_OUT="$2"; shift 2;; --out-right-fifo) RIGHT_OUT="$2"; shift 2;; *) shift;; esac; done
if [ -n "$LEFT_IN" ] && [ -n "$LEFT_OUT" ]; then ( while :; do dd if="$LEFT_IN" of="$LEFT_OUT" bs=4096 status=none || sleep 1; done ) & fi
if [ -n "$RIGHT_IN" ] && [ -n "$RIGHT_OUT" ]; then ( while :; do dd if="$RIGHT_IN" of="$RIGHT_OUT" bs=4096 status=none || sleep 1; done ) & fi
wait
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
if ! [[ "\${INGEST_DELAY_SEC}" =~ ^[0-9]+$ ]]; then
  INGEST_DELAY_SEC=10
fi
INGEST_DELAY_MS=$((INGEST_DELAY_SEC * 1000))
if [ "${RADIO}" = "1" ]; then
  SINK_NAME="ompx_prg1in"
else
  SINK_NAME="ompx_prg2in"
fi
if ! aplay -L 2>/dev/null | grep -q "^\${SINK_NAME}$"; then
  if [ "${RADIO}" = "1" ]; then
    SINK_NAME="plughw:${LOOPBACK_CARD_REF},0,0"
  else
    SINK_NAME="plughw:${LOOPBACK_CARD_REF},0,1"
  fi
  echo "[\$(date +'%F %T')] source${RADIO}: named sink unavailable; using fallback \${SINK_NAME}"
fi
echo "[\$(date +'%F %T')] source${RADIO}: using ALSA output endpoint \${SINK_NAME}"
echo "[\$(date +'%F %T')] source${RADIO}: ingest via ffmpeg (input format auto-detected, delay \${INGEST_DELAY_SEC}s)"
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
RDS_PROG1_INTERVAL_SEC="${RDS_PROG1_INTERVAL_SEC:-5}"
RDS_PROG1_RT_PATH="${RDS_PROG1_RT_PATH:-/home/ompx/rds/prog1/rt.txt}"
RADIO1_URL="${RADIO1_URL:-}"

_log(){ logger -t rds-sync-prog1 "$*"; echo "$(date +'%F %T') [rds-sync-prog1] $*"; }

_fetch_stream_title(){
  local stream_url="$1"
  local title=""
  title="$(timeout 20 ffprobe -v error -show_entries format_tags=StreamTitle -of default=noprint_wrappers=1:nokey=1 "${stream_url}" 2>/dev/null | head -n1 | tr -d '\r' || true)"
  if [ -z "${title}" ]; then
    title="$(timeout 20 ffmpeg -nostdin -hide_banner -loglevel info -i "${stream_url}" -t 8 -vn -sn -dn -f null - 2>&1 | sed -n "s/.*StreamTitle='\([^']*\)'.*/\1/p" | head -n1 | tr -d '\r' || true)"
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

if [ "${RDS_PROG1_SOURCE}" != "metadata" ] && [ -z "${RDS_PROG1_RT_URL}" ]; then
  _log "RDS_PROG1_RT_URL is empty; exiting"
  exit 0
fi

if ! [[ "${RDS_PROG1_INTERVAL_SEC}" =~ ^[0-9]+$ ]] || [ "${RDS_PROG1_INTERVAL_SEC}" -lt 1 ]; then
  RDS_PROG1_INTERVAL_SEC=5
fi

mkdir -p "$(dirname "${RDS_PROG1_RT_PATH}")"
tmp_path="${RDS_PROG1_RT_PATH}.tmp"

while true; do
  if [ "${RDS_PROG1_SOURCE}" = "metadata" ]; then
    rt_text="$(_fetch_stream_title "${RADIO1_URL}")"
    if [ -n "${rt_text}" ]; then
      printf '%s\n' "${rt_text}" > "${tmp_path}"
      mv -f "${tmp_path}" "${RDS_PROG1_RT_PATH}"
    else
      _log "No StreamTitle metadata found from RADIO1_URL"
    fi
  else
    if wget -q -T 20 -O "${tmp_path}" "${RDS_PROG1_RT_URL}"; then
      mv -f "${tmp_path}" "${RDS_PROG1_RT_PATH}"
    else
      _log "Failed to fetch ${RDS_PROG1_RT_URL}"
    fi
  fi
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
RDS_PROG2_INTERVAL_SEC="${RDS_PROG2_INTERVAL_SEC:-5}"
RDS_PROG2_RT_PATH="${RDS_PROG2_RT_PATH:-/home/ompx/rds/prog2/rt.txt}"
RADIO2_URL="${RADIO2_URL:-}"

_log(){ logger -t rds-sync-prog2 "$*"; echo "$(date +'%F %T') [rds-sync-prog2] $*"; }

_fetch_stream_title(){
  local stream_url="$1"
  local title=""
  title="$(timeout 20 ffprobe -v error -show_entries format_tags=StreamTitle -of default=noprint_wrappers=1:nokey=1 "${stream_url}" 2>/dev/null | head -n1 | tr -d '\r' || true)"
  if [ -z "${title}" ]; then
    title="$(timeout 20 ffmpeg -nostdin -hide_banner -loglevel info -i "${stream_url}" -t 8 -vn -sn -dn -f null - 2>&1 | sed -n "s/.*StreamTitle='\([^']*\)'.*/\1/p" | head -n1 | tr -d '\r' || true)"
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

if [ "${RDS_PROG2_SOURCE}" != "metadata" ] && [ -z "${RDS_PROG2_RT_URL}" ]; then
  _log "RDS_PROG2_RT_URL is empty; exiting"
  exit 0
fi

if ! [[ "${RDS_PROG2_INTERVAL_SEC}" =~ ^[0-9]+$ ]] || [ "${RDS_PROG2_INTERVAL_SEC}" -lt 1 ]; then
  RDS_PROG2_INTERVAL_SEC=5
fi

mkdir -p "$(dirname "${RDS_PROG2_RT_PATH}")"
tmp_path="${RDS_PROG2_RT_PATH}.tmp"

while true; do
  if [ "${RDS_PROG2_SOURCE}" = "metadata" ]; then
    rt_text="$(_fetch_stream_title "${RADIO2_URL}")"
    if [ -n "${rt_text}" ]; then
      printf '%s\n' "${rt_text}" > "${tmp_path}"
      mv -f "${tmp_path}" "${RDS_PROG2_RT_PATH}"
    else
      _log "No StreamTitle metadata found from RADIO2_URL"
    fi
  else
    if wget -q -T 20 -O "${tmp_path}" "${RDS_PROG2_RT_URL}"; then
      mv -f "${tmp_path}" "${RDS_PROG2_RT_PATH}"
    else
      _log "Failed to fetch ${RDS_PROG2_RT_URL}"
    fi
  fi
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
systemctl enable --now mpx-source2.service || true
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
echo "     Ingest delay is controlled by INGEST_DELAY_SEC in ${OMPX_HOME}/.profile (current/default: ${INGEST_DELAY_SEC}s)"
echo "     After changing it, restart ingest: systemctl restart mpx-source1.service mpx-source2.service"
echo ""
echo "  2. Check service status:"
if has_systemd; then
  echo "     systemctl status mpx-processing-alsa.service"
  echo "     systemctl status mpx-watchdog.service"
  echo "     systemctl status mpx-stream-pull.service"
  echo "     systemctl status rds-sync-prog1.service"
  echo "     systemctl status rds-sync-prog2.service"
  echo "     systemctl status stereo-tool-enterprise.service"
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
echo "     aplay -L | grep -E 'ompx_prg1in|ompx_prg2in|ompx_prg1prev|ompx_prg2prev|ompx_prg1mpx|ompx_prg2mpx|ompx_dsca_src|ompx_dsca_injection|ompx_mpx_to_icecast'"
echo "     arecord -L | grep -E 'ompx_prg1in_cap|ompx_prg2in_cap|ompx_prg1prev_cap|ompx_prg2prev_cap|ompx_dsca_src_cap'"
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
echo "     RDS source mode is per-program: URL text file or stream metadata (StreamTitle)."
echo "     Metadata mode reads Program 1 from RADIO1_URL and Program 2 from RADIO2_URL."
echo "     If your processor can read RadioText from a file, point it at those paths."
echo "     Stereo Tool example strings:"
echo "       Program 1: \\r\"/home/ompx/rds/prog1/rt.txt\""
echo "       Program 2: \\r\"/home/ompx/rds/prog2/rt.txt\""
echo "     Note: this installer uses 'prog1' and 'prog2' in the directory names."
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