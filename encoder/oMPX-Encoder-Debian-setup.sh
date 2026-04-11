
#!/usr/bin/env bash
set -euo pipefail
# oMPX unified installer + ALSA asound.conf setup (192kHz sample rate, 80kHz subcarrier frequency)
# Requires: Debian/Ubuntu or bare metal with standard kernel (not Proxmox PVE, and yes we know Proxmox is based on Debian, but their custom kernel often lacks snd_aloop which is critical for this setup)
# For best results, use a standard Debian kernel (linux-image-amd64) that includes snd_aloop
# Date: 2026-04-07

echo "[$(date +'%F %T')] oMPX installer starting..."
# --- Configurable variables ---

OMPX_USER="oMPX"
OMPX_HOME="/var/lib/ompx"
OMPX_LOG_DIR="${OMPX_HOME}/logs"
RADIO_URL_VALUE="${!RADIO_VAR_NAME:-}"
  slave.channels 2
  hint { show on; description "Program 1 Input" }
}
  echo "[$(date +'%F %T')] source${n}: RADIO${n}_URL is empty/placeholder; exiting"
  type plug
RADIO_URL_VALUE="${!RADIO_VAR_NAME:-}"
  if [ -n "${card}" ]; then
    printf '  %-15s -> hw:%s,0\n' "$id" "$card"
  else
  echo "[$(date +'%F %T')] source${n}: RADIO${n}_URL is empty/placeholder; exiting"
done
count=$(awk -F'[][]' '/program1in|program1preview|program2in|program2preview|dscasource|program1mpxsrc|program2mpxsrc|dscainjectionsrc|mpxmix|ompxaux1|ompxaux2/{c++} END{print c+0}' /proc/asound/cards 2>/dev/null)
if [ "${count:-0}" -lt 6 ]; then
  echo ""
  echo "WARNING: kernel currently exposes ${count:-0} oMPX loopback cards; it may have collapsed to a single Loopback card with subdevices."
fi
ASMAP
chmod 755 "${ASOUND_MAP_HELPER}"
chown root:root "${ASOUND_MAP_HELPER}"
echo "[SUCCESS] Created ${ASOUND_MAP_HELPER} helper"

if [ "$CONFIG_OVERWRITE" = false ]; then
echo "[INFO] Keeping existing ALSA configuration unchanged"
echo "[INFO] Staged test profile only. Promote it with: sudo ${ASOUND_SWITCH_HELPER}"
else
echo "[INFO] Writing /etc/asound.conf..."

if [ -f "${ASOUND_CONF_PATH}" ]; then
if ! cmp -s <(printf '%s' "${WANT_ASOUND_TEST}") "${ASOUND_CONF_PATH}"; then
if [ "$CONFIG_BACKUP" = true ]; then
cp -a "${ASOUND_CONF_PATH}" "${ASOUND_CONF_PATH}.bak.$(date +%s)" || true
echo "[INFO] Backed up existing ${ASOUND_CONF_PATH}"
fi
printf '%s' "${WANT_ASOUND_TEST}" > "${ASOUND_CONF_PATH}"
chmod 644 "${ASOUND_CONF_PATH}" || true
_log "Updated ${ASOUND_CONF_PATH}."
echo "[SUCCESS] ALSA config updated"
else
_log "${ASOUND_CONF_PATH} already matches desired content."
echo "[INFO] ALSA config already current"
fi
else
printf '%s' "${WANT_ASOUND_TEST}" > "${ASOUND_CONF_PATH}"
chmod 644 "${ASOUND_CONF_PATH}" || true
_log "Wrote ${ASOUND_CONF_PATH}."
echo "[SUCCESS] ALSA config created"
fi
fi
fi
# --- Check existing installation ---
echo "[INFO] Checking for existing oMPX installation..."

found=0
msg=""
if id -u "${OMPX_USER}" >/dev/null 2>&1; then found=1; msg="${msg}user:${OMPX_USER} "; fi
if [ -d "${SYS_SCRIPTS_DIR}" ]; then found=1; msg="${msg}${SYS_SCRIPTS_DIR} "; fi
if systemctl list-unit-files | grep -q '^mpx-processing-alsa.service'; then found=1; msg="${msg}mpx-processing-alsa.service "; fi
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
systemctl stop mpx-processing-alsa.service mpx-watchdog.service 2>/dev/null || true
echo "[INFO] Disabling systemd services..."
systemctl disable mpx-processing-alsa.service mpx-watchdog.service 2>/dev/null || true
rm -f "${SYSTEMD_DIR}/mpx-processing-alsa.service" "${SYSTEMD_DIR}/mpx-watchdog.service"
systemctl daemon-reload || true
echo "[INFO] Removing old cron jobs..."
if have_crontab && id -u "${OMPX_USER}" >/dev/null 2>&1; then
crontab -u "${OMPX_USER}" -l 2>/dev/null | grep -v "${SYS_SCRIPTS_DIR}/source" | sed '/^$/d' | crontab -u "${OMPX_USER}" - 2>/dev/null || true
else
echo "[WARNING] crontab command not found; skipping cron cleanup"
fi
echo "[INFO] Removing old files and directories..."
rm -f "${STEREO_TOOL_WRAPPER}" "${STEREO_TOOL_WRAPPER}.real-check" "${OMPX_ADD}"
rm -rf "${SYS_SCRIPTS_DIR}" "${LIQUIDSOAP_CONF_DIR}" "${OMPX_LOG_DIR}" /var/log/radio-opus1.log /var/log/radio-opus2.log
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
systemctl stop mpx-processing-alsa.service mpx-watchdog.service 2>/dev/null || true
echo "[INFO] Disabling systemd services..."
systemctl disable mpx-processing-alsa.service mpx-watchdog.service 2>/dev/null || true
rm -f "${SYSTEMD_DIR}/mpx-processing-alsa.service" "${SYSTEMD_DIR}/mpx-watchdog.service"
systemctl daemon-reload || true
echo "[INFO] Removing cron jobs..."
if have_crontab && id -u "${OMPX_USER}" >/dev/null 2>&1; then
crontab -u "${OMPX_USER}" -l 2>/dev/null | grep -v "${SYS_SCRIPTS_DIR}/source" | sed '/^$/d' | crontab -u "${OMPX_USER}" - 2>/dev/null || true
else
echo "[WARNING] crontab command not found; skipping cron cleanup"
fi
echo "[INFO] Removing files and directories..."
rm -f "${STEREO_TOOL_WRAPPER}" "${STEREO_TOOL_WRAPPER}.real-check" "${OMPX_ADD}"
rm -rf "${SYS_SCRIPTS_DIR}" "${LIQUIDSOAP_CONF_DIR}" "${OMPX_LOG_DIR}" /var/log/radio-opus1.log /var/log/radio-opus2.log
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
useradd --system --home "${OMPX_HOME}" --create-home --shell "${OMPX_SHELL}" --comment "oMPX service account" "${OMPX_USER}"
echo "[SUCCESS] User ${OMPX_USER} created"
else
echo "[INFO] User ${OMPX_USER} already exists; ensuring shell is ${OMPX_SHELL}."
_log "User ${OMPX_USER} exists; ensuring shell is ${OMPX_SHELL}."
usermod -s "${OMPX_SHELL}" "${OMPX_USER}" || true
echo "[SUCCESS] User shell updated"
fi
# --- Write profile (overwrite) ---
echo "[INFO] Creating user profile configuration..."

mkdir -p "${OMPX_HOME}"
PROFILE="${OMPX_HOME}/.profile"
cp -a "${PROFILE:-/dev/null}" "${PROFILE}.bak.$(date +%s)" 2>/dev/null || true
cat > "$PROFILE" <<PROFILE_WRITTEN
# oMPX persistent environment (auto-generated)

RADIO1_URL="${RADIO1_URL}"
RADIO2_URL="${RADIO2_URL}"
PROFILE_WRITTEN
chown "${OMPX_USER}:${OMPX_USER}" "$PROFILE"; chmod 644 "$PROFILE"
_log "Wrote profile ${PROFILE}."
echo "[SUCCESS] Profile configuration created"
# --- Create directories, install packages ---
echo "[INFO] Creating system directories..."

mkdir -p "${SYS_SCRIPTS_DIR}" "${FIFOS_DIR}" "${LIQUIDSOAP_CONF_DIR}" "${OMPX_LOG_DIR}"
chown -R "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}"
chown -R "${OMPX_USER}:${OMPX_USER}" "${OMPX_LOG_DIR}"
chmod 755 "${SYS_SCRIPTS_DIR}" "${FIFOS_DIR}" "${LIQUIDSOAP_CONF_DIR}"
chmod 755 "${OMPX_LOG_DIR}"
echo "[SUCCESS] Directories created at ${SYS_SCRIPTS_DIR}"

echo "[INFO] Updating package lists..."
safe_apt_update
echo "[INFO] Installing base dependencies (curl, alsa-utils, ffmpeg, sox, ladspa-sdk, swh-plugins, liquidsoap, cron)..."
DEBIAN_FRONTEND=noninteractive apt install -y curl alsa-utils ffmpeg sox ladspa-sdk swh-plugins liquidsoap cron
if [ -n "${KERNEL_HELPER_PACKAGE}" ]; then
  echo "[INFO] Installing kernel helper package for this OS: ${KERNEL_HELPER_PACKAGE}"
  DEBIAN_FRONTEND=noninteractive apt install -y "${KERNEL_HELPER_PACKAGE}" || echo "[WARNING] Optional package ${KERNEL_HELPER_PACKAGE} could not be installed"
else
  echo "[INFO] No automatic kernel helper package selected for this environment"
fi
echo "[SUCCESS] Dependencies installed"
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

sleep 1
echo "[INFO] Available ALSA devices:"
aplay -l 2>/dev/null || echo "[WARNING] No ALSA devices found"
echo "[INFO] Hardware-only list above (aplay -l). Virtual named PCMs are shown with: aplay -L"
_log "ALSA devices listed above"
echo "[INFO] Expected named ALSA PCMs: prg1in, prg1in_cap, prg2in, prg2in_cap, prg1prev, prg1prev_cap, prg2prev, prg2prev_cap, prg1mpx, prg2mpx, dsca_src, dsca_src_cap, dsca_injection, mpx_to_icecast"
echo "[INFO] Resolved sink map helper: ${ASOUND_MAP_HELPER}"
"${ASOUND_MAP_HELPER}" || true
# --- Create FIFOs for liquidsoap outputs ---
echo "[INFO] Creating FIFOs for radio streams..."

for r in 1 2; do
fifo="${FIFOS_DIR}/radio${r}.pcm"
rm -f "$fifo" || true
mkfifo -m 660 "$fifo"
chown "${OMPX_USER}:${OMPX_USER}" "$fifo"
echo "[SUCCESS] Created FIFO: $fifo"
done
# --- Liquidsoap configuration files (safe templates) ---
echo "[INFO] Generating Liquidsoap configuration files..."

cat > "${LIQUIDSOAP_CONF_DIR}/radio1.liq" <<'L1'
set("log.stdout", true)
sample_rate = 192000
fifo_path = "/opt/mpx-radio/fifos/radio1.pcm"
def write_fifo(fifo, src)
cmd = "ffmpeg -hide_banner -loglevel warning -i - -f s16le -ac 2 -ar " ^ string_of_int(sample_rate) ^ " - 2>/dev/null > '" ^ fifo ^ "'"
output.exec(src, ["sh","-c", cmd])
end
default_url = "${RADIO1_URL}"
urL = if getenv("RADIO_URL", "") <> "" then getenv("RADIO_URL") else default_url
s1 = request.create(urL)
s1 = fallback(track_sensitive = true, [s1, blank(duration = 3600.)])
s1 = convert(s1, samplerate = sample_rate, channels = 2)
write_fifo(fifo_path, s1)
output.null(s1)
L1

cat > "${LIQUIDSOAP_CONF_DIR}/radio2.liq" <<'L2'
set("log.stdout", true)
sample_rate = 192000
fifo_path = "/opt/mpx-radio/fifos/radio2.pcm"
def write_fifo(fifo, src)
cmd = "ffmpeg -hide_banner -loglevel warning -i - -f s16le -ac 2 -ar " ^ string_of_int(sample_rate) ^ " - 2>/dev/null > '" ^ fifo ^ "'"
output.exec(src, ["sh","-c", cmd])
end
default_url = "${RADIO2_URL}"
urL = if getenv("RADIO_URL", "") <> "" then getenv("RADIO_URL") else default_url
s1 = request.create(urL)
s1 = fallback(track_sensitive = true, [s1, blank(duration = 3600.)])
s1 = convert(s1, samplerate = sample_rate, channels = 2)
write_fifo(fifo_path, s1)
output.null(s1)
L2
echo "[SUCCESS] Liquidsoap configs created (radio1.liq, radio2.liq)"

echo "[INFO] Creating oMPX encoder Liquidsoap script..."
cat > "${OMPX_ENCODER_LIQ}" <<'OMPX_LIQ'
# /usr/local/bin/ompx_encoder.liq
# oMPX named ALSA sinks for this installer profile:
#   prg1in, prg2in, prg1prev, prg2prev, prg1mpx, prg2mpx, dsca_src, dsca_injection, mpx_to_icecast
# Main stereo source: capture side of Program 1 input loopback sink.
main = input.alsa(device="prg1in_cap")

# Injector source: capture side of DSCA source loopback sink.
injector_mono = input.alsa(device="dsca_src_cap")

# Ensure both sources are resampled to 192kHz first for correct filtering and mixing
main = convert_samplerate(main, 192000)
injector_mono = convert_samplerate(injector_mono, 192000)

# If main is mono, keep it mono and append a silent channel so output stays stereo (dead channel preserved)
main = if channels(main) == 2 then main else add_blank_channel(main) end

# Band-pass the injector around ~80kHz (center 80000 Hz, narrow band e.g. ±5kHz)
# Use highpass + lowpass to create a band-pass.
inj = highpass(injector_mono, 75000.)
inj = lowpass(inj, 85000.)

# Convert injector to 2 channels by duplicating mono into both channels (so it adds to both L and R)
inj_stereo = stereoize(inj)

# Mix injector into main at a controlled gain (e.g., -6 dB to avoid clipping)
inj_stereo = amplify(0.5, inj_stereo)

# Add injector to main without altering original channels otherwise
out_src = add([main, inj_stereo])

# Final safety: ensure out_src is 2-channel and 192kHz
out_src = if channels(out_src) == 2 then out_src else add_blank_channel(out_src) end
out_src = convert_samplerate(out_src, 192000)

# Composite clipper: split 0-16kHz (composite+stereo subcarrier) from 16kHz+ (RDS+pilot)
# Only clip the composite band; leave RDS and pilot unclipped.

# Composite band: 0-16 kHz (composite audio + 38 kHz stereo pilot region)
composite_band = lowpass(out_src, 16000.)
composite_band = clip(composite_band, min=-0.99, max=0.99)

# Protected band: 16 kHz+ (RDS at ~57kHz, pilot at ~19kHz, and beyond)
protected_band = highpass(out_src, 16000.)

# Recombine clipped composite + unclipped highs
out_src = add([composite_band, protected_band])

# Stream as FLAC to Icecast
output.icecast(
  %flac(compression=8),
  mount="/mpx",
  host="127.0.0.1",
  port=8000,
  password="bbkrb494b3fy8qqcrym6fvbfgdxk7jcher-mpx",
  name="MPX FLAC 192kHz (stereo with 80kHz injector)",
  description="Native 192kHz FLAC stereo (L=PROG1, R=PROG2) with shared ~80kHz injection and composite clipping",
  genre="Radio",
  url="http://127.0.0.1:8000/mpx",
  out_src
)
OMPX_LIQ
chown "${OMPX_USER}:${OMPX_USER}" "${OMPX_ENCODER_LIQ}"
chmod 640 "${OMPX_ENCODER_LIQ}"

cat > "${OMPX_ENCODER_RUN}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [ "\$(id -un)" != "${OMPX_USER}" ]; then
  exec runuser -u "${OMPX_USER}" -- /usr/bin/liquidsoap "${OMPX_ENCODER_LIQ}"
fi

exec /usr/bin/liquidsoap "${OMPX_ENCODER_LIQ}"
EOF
chown root:root "${OMPX_ENCODER_RUN}"
chmod 755 "${OMPX_ENCODER_RUN}"
echo "[SUCCESS] Created ${OMPX_ENCODER_LIQ} and ${OMPX_ENCODER_RUN} (runs as ${OMPX_USER})"
# --- Create source wrapper scripts (persistent ffmpeg ingest to ALSA sinks) ---
echo "[INFO] Creating wrapper scripts..."

for n in 1 2; do
cat > "${SYS_SCRIPTS_DIR}/source${n}.sh" <<WRAP
#!/usr/bin/env bash
set -euo pipefail
PROFILE="${OMPX_HOME}/.profile"
[ -f "$PROFILE" ] && . "$PROFILE"
RADIO_VAR_NAME="RADIO${n}_URL"
RADIO_URL_VALUE="
  "; RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  " # keep shellcheck quiet in generated file context
RADIO_URL_VALUE="
  " # overwritten on next line at runtime
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="
  "
RADIO_URL_VALUE="${!RADIO_VAR_NAME:-}"
SINK_NAME="prg${n}in"

if [ -z "${RADIO_URL_VALUE}" ] || [[ "${RADIO_URL_VALUE}" == *"example-icecast.local"* ]] || [[ "${RADIO_URL_VALUE}" == *"your.stream/url"* ]]; then
  echo "[
    t	date +'%F %T'] source${n}: RADIO${n}_URL is empty/placeholder; exiting"
  exit 0
fi

while true; do
  ffmpeg -re -thread_queue_size 10240 -i "${RADIO_URL_VALUE}" \
    -content_type "audio/ogg" \
    -max_delay 5000000 \
    -ar ${SAMPLE_RATE} -ac 2 -f alsa "${SINK_NAME}" || true
  sleep 5
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
PROG1_FIFO="/opt/mpx-radio/fifos/radio1.pcm"
PROG2_FIFO="/opt/mpx-radio/fifos/radio2.pcm"
MPX_LEFT_MONO="/tmp/mpx_left.pcm"; MPX_RIGHT_MONO="/tmp/mpx_right.pcm"
MPX_LEFT_OUT="${MPX_LEFT_MONO}.out"; MPX_RIGHT_OUT="${MPX_RIGHT_MONO}.out"
MPX_STEREO_FIFO="/tmp/mpx_stereo.pcm"
_log(){ logger -t mpx "$*"; echo "$(date +'%F %T') $*"; }
for p in "$MPX_LEFT_MONO" "$MPX_RIGHT_MONO" "$MPX_LEFT_OUT" "$MPX_RIGHT_OUT" "$MPX_STEREO_FIFO"; do rm -f "$p" || true; mkfifo "$p"; done
wait_for_fifo(){ local f="$1"; local timeout=${2:-30}; local e=0; while [ ! -p "$f" ] && [ $e -lt $timeout ]; do sleep 1; e=$((e+1)); done; [ -p "$f" ]; }
wait_for_fifo "$PROG1_FIFO" 60 || exit 1
ffmpeg -hide_banner -loglevel warning -f s16le -ar ${SAMPLE_RATE} -ac 2 -i "${PROG1_FIFO}" -map_channel 0.0.0 -f s16le -ac 1 - > "${MPX_LEFT_MONO}" &
FF_PROG1_MONO_PID=$!; _log "Spawned PROG1 mono extractor pid $FF_PROG1_MONO_PID"
if wait_for_fifo "$PROG2_FIFO" 10; then
ffmpeg -hide_banner -loglevel warning -f s16le -ar ${SAMPLE_RATE} -ac 2 -i "${PROG2_FIFO}" -map_channel 0.0.0 -f s16le -ac 1 - > "${MPX_RIGHT_MONO}" &
FF_PROG2_MONO_PID=$!; _log "Spawned PROG2 mono extractor pid ${FF_PROG2_MONO_PID:-0}"
else
( while :; do dd if=/dev/zero bs=4096 count=256 status=none; sleep 0.1; done ) > "${MPX_RIGHT_MONO}" &
SILENCE_PID=$!
fi
"${STEREO_TOOL_CMD}" --mode live --left-fifo "${MPX_LEFT_MONO}" --right-fifo "${MPX_RIGHT_MONO}" --out-left-fifo "${MPX_LEFT_OUT}" --out-right-fifo "${MPX_RIGHT_OUT}" &
STEREO_PID=$!; _log "Started stereo-tool wrapper pid ${STEREO_PID}"
ffmpeg -hide_banner -loglevel warning -f s16le -ar ${SAMPLE_RATE} -ac 1 -i "${MPX_LEFT_OUT}" -f s16le -ar ${SAMPLE_RATE} -ac 1 -i "${MPX_RIGHT_OUT}" -filter_complex "[0:a][1:a]join=inputs=2:channel_layout=stereo[aout]" -map "[aout]" -f s16le -ar ${SAMPLE_RATE} -ac 2 - > "${MPX_STEREO_FIFO}" &
FF_MERGE_PID=$!; _log "ffmpeg merge pid $FF_MERGE_PID"
ALSA_OUTPUT="${ALSA_OUTPUT:-}"
if [ -z "$ALSA_OUTPUT" ]; then if aplay -l 2>/dev/null | grep -qi loopback; then ALSA_OUTPUT="hw:Loopback,0,0"; fi; fi
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
# --- systemd units ---
echo "[INFO] Creating systemd service files..."

cat > "${SYSTEMD_DIR}/mpx-processing-alsa.service" <<EOF
[Unit]
Description=MPX processing (ALSA/ffmpeg) (oMPX)
After=network-online.target
[Service]
User=${OMPX_USER}
Group=${OMPX_USER}
Type=simple
ExecStart=${SYS_SCRIPTS_DIR}/run_processing_alsa_liquid.sh
Restart=on-failure
RestartSec=2
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF

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

cat > "${SYS_SCRIPTS_DIR}/mpx-watchdog.sh" <<'WD'
#!/usr/bin/env bash
set -euo pipefail
SLEEP=20
while true; do
if ! systemctl is-active --quiet mpx-processing-alsa.service; then
logger -t mpx "Watchdog: restarting processing service"
systemctl restart mpx-processing-alsa.service || logger -t mpx "Watchdog: failed to restart"
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
SYS_SCRIPTS_DIR="/opt/mpx-radio"; OMPX_USER="oMPX"; OMPX_HOME="/var/lib/ompx"; OMPX_LOG_DIR="${OMPX_HOME}/logs"; CRON_SLEEP=10; LIQUIDSOAP_CONF_DIR="/opt/mpx-radio/liquidsoap"
usage(){ cat <<USAGE
Usage: $0 --radio 1|2 --url URL [--cron-user root|oMPX] [--start-now]
Adds or updates an existing radio source URL and wrapper.
USAGE
}
RADIO=""; URL=""; CRON_USER="${OMPX_USER}"; START_NOW=0
while [ $# -gt 0 ]; do case "$1" in --radio) RADIO="$2"; shift 2;; --url) URL="$2"; shift 2;; --cron-user) CRON_USER="$2"; shift 2;; --start-now) START_NOW=1; shift;; -h|--help) usage; exit 0;; *) echo "Unknown arg: $1"; usage; exit 1;; esac; done
if [ -z "$RADIO" ] || [ -z "$URL" ]; then usage; exit 1; fi
PROFILE="${OMPX_HOME}/.profile"; cp -a "$PROFILE" "${PROFILE}.bak.$(date +%s)"
VAR="RADIO${RADIO}_URL"
if grep -q "^${VAR}=" "$PROFILE"; then sed -i "s|^${VAR}=.*|${VAR}=\"${URL}\"|" "$PROFILE"; else echo "${VAR}=\"${URL}\"" >> "$PROFILE"; fi
chown ${OMPX_USER}:${OMPX_USER} "$PROFILE"; chmod 644 "$PROFILE"
WRAPPER="${SYS_SCRIPTS_DIR}/source${RADIO}.sh"
LOG_FILE="${OMPX_LOG_DIR}/radio-opus${RADIO}.log"
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
SINK_NAME="prg${RADIO}in"
if [ -z "\${RADIO_URL_VALUE}" ] || [[ "\${RADIO_URL_VALUE}" == *"example-icecast.local"* ]] || [[ "\${RADIO_URL_VALUE}" == *"your.stream/url"* ]]; then
  echo "[$(date +'%F %T')] source${RADIO}: RADIO${RADIO}_URL is empty/placeholder; exiting"
  exit 0
fi
while true; do
  ffmpeg -re -thread_queue_size 10240 -i "\${RADIO_URL_VALUE}" \
    -content_type "audio/ogg" \
    -max_delay 5000000 \
    -ar 192000 -ac 2 -f alsa "\${SINK_NAME}" || true
  sleep 5
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

OMPX_USER="oMPX"
SYS_SCRIPTS_DIR="/opt/mpx-radio"
OMPX_LOG_DIR="/var/lib/ompx/logs"

usage(){ cat <<USAGE
Usage: $0 [--start] [--shell]
--start   Ensure source1.sh and source2.sh are running (background, logs)
--shell   Drop to an interactive shell as oMPX (equivalent to su - oMPX)
If neither flag given, acts as --start.
USAGE
}

start_sources(){
mkdir -p "${OMPX_LOG_DIR}"
chown "${OMPX_USER}:${OMPX_USER}" "${OMPX_LOG_DIR}" 2>/dev/null || true
for n in 1 2; do
wrapper="${SYS_SCRIPTS_DIR}/source${n}.sh"
log="${OMPX_LOG_DIR}/radio-opus${n}.log"
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
# --- Install @reboot cron for oMPX to start sources at boot ---
echo "[INFO] Setting up cron jobs..."

CRON_LINE1="@reboot sleep ${CRON_SLEEP} && ${SYS_SCRIPTS_DIR}/start_or_shell.sh --start >>${OMPX_LOG_DIR}/radio-opus-start.log 2>&1 &"
if have_crontab; then
existing=$(crontab -u "${OMPX_USER}" -l 2>/dev/null || true)
new_cron="${existing}"
echo "$existing" | grep -F -q "${SYS_SCRIPTS_DIR}/source1.sh" >/dev/null 2>&1 || new_cron="${new_cron}
${CRON_LINE1}"
printf "%s\n" "${new_cron}" | sed '/^$/d' | crontab -u "${OMPX_USER}" -
echo "[SUCCESS] Cron job configured for ${OMPX_USER}"
else
echo "[WARNING] crontab command not found; skipping cron job setup"
fi
# --- Enable and start services ---
echo "[INFO] Enabling and starting systemd services..."

systemctl daemon-reload
echo "[INFO] Enabling mpx-processing-alsa.service..."
systemctl enable --now mpx-processing-alsa.service || true
echo "[INFO] Enabling mpx-watchdog.service..."
systemctl enable --now mpx-watchdog.service || true

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
echo ""
echo "  2. Check service status:"
echo "     systemctl status mpx-processing-alsa.service"
echo "     systemctl status mpx-watchdog.service"
echo ""
echo "  3. View logs:"
echo "     journalctl -u mpx-processing-alsa.service -f"
echo ""
echo "  4. Verify ALSA named sinks:"
echo "     aplay -L | grep -E 'prg1in|prg2in|prg1prev|prg2prev|prg1mpx|prg2mpx|dsca_src|dsca_injection|mpx_to_icecast'"
echo ""
echo "  5. Print resolved sink-to-hardware map:"
echo "     sudo ${ASOUND_MAP_HELPER}"
echo ""
echo "  6. Access oMPX user shell:"
echo "     sudo su - oMPX"
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
    echo "[INFO] Restarting oMPX services to apply runtime changes..."
    systemctl restart mpx-processing-alsa.service mpx-watchdog.service 2>/dev/null || true
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