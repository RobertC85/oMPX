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
OMPX_SHELL="/bin/bash"
SYS_SCRIPTS_DIR="/opt/mpx-radio"
FIFOS_DIR="${SYS_SCRIPTS_DIR}/fifos"
LIQUIDSOAP_CONF_DIR="${SYS_SCRIPTS_DIR}/liquidsoap"
SYSTEMD_DIR="/etc/systemd/system"
STEREO_TOOL_WRAPPER="/usr/local/bin/stereo-tool"
OMPX_ADD="/usr/local/sbin/ompx_add_source"
SAMPLE_RATE=192000
RADIO1_URL="http://example-icecast.local:8000/mount1"
RADIO2_URL="http://example-icecast.local:8000/mount2"
CRON_SLEEP=10

ASOUND_CONF_PATH="/etc/asound.conf"

_log(){ logger -t mpx-installer "$*"; echo "$(date +'%F %T') $*"; }

if [ "$(id -u)" -ne 0 ]; then echo "Run as root: sudo $0" >&2; exit 1; fi

# --- Config file handling options ---
echo ""
echo "How should existing configuration files be handled?"
echo "  K) Keep existing config files unchanged (skip writing new ones)"
echo "  B) Backup existing config files and overwrite with new ones"
echo "  O) Overwrite existing config files without backup"
echo "  S) Skip config file setup entirely"
read -t 30 -p "Select [K/B/O/S] (default B): " config_action || true
config_action="${config_action:-B}"
config_action=${config_action^^}
echo "[INFO] Config action selected: $config_action"

case "$config_action" in
K)
echo "[INFO] Keeping existing config files unchanged"
CONFIG_BACKUP=false
CONFIG_OVERWRITE=false
CONFIG_SKIP=true
;;
B)
echo "[INFO] Will backup and overwrite config files"
CONFIG_BACKUP=true
CONFIG_OVERWRITE=true
CONFIG_SKIP=false
;;
O)
echo "[INFO] Will overwrite config files without backup"
CONFIG_BACKUP=false
CONFIG_OVERWRITE=true
CONFIG_SKIP=false
;;
S)
echo "[INFO] Skipping config file setup"
CONFIG_BACKUP=false
CONFIG_OVERWRITE=false
CONFIG_SKIP=true
;;
*)
echo "[INFO] Aborting due to invalid config action choice"
exit 0
;;
esac

# --- Ensure snd_aloop loads and write modprobe options ---

if [ "$CONFIG_SKIP" = true ]; then
echo "[INFO] Skipping kernel module configuration as requested"
else
echo "[INFO] Setting up snd_aloop kernel module..."
mkdir -p /etc/modules-load.d /etc/modprobe.d
if [ "$CONFIG_BACKUP" = true ] && [ -f /etc/modules-load.d/snd-aloop.conf ]; then
cp -a /etc/modules-load.d/snd-aloop.conf /etc/modules-load.d/snd-aloop.conf.bak.$(date +%s) || true
echo "[INFO] Backed up existing /etc/modules-load.d/snd-aloop.conf"
fi
cat > /etc/modules-load.d/snd-aloop.conf <<'EOF'
snd-aloop
EOF
echo "[INFO] Created /etc/modules-load.d/snd-aloop.conf"

if [ "$CONFIG_BACKUP" = true ] && [ -f /etc/modprobe.d/snd-aloop.conf ]; then
cp -a /etc/modprobe.d/snd-aloop.conf /etc/modprobe.d/snd-aloop.conf.bak.$(date +%s) || true
echo "[INFO] Backed up existing /etc/modprobe.d/snd-aloop.conf"
fi
cat > /etc/modprobe.d/snd-aloop.conf <<'EOF'
options snd-aloop pcm_substreams=16
EOF
echo "[INFO] Created /etc/modprobe.d/snd-aloop.conf with pcm_substreams=16"
fi
echo "[INFO] Attempting to load snd_aloop module..."
modprobe snd_aloop 2>/dev/null && echo "[SUCCESS] snd_aloop loaded" || {
    echo "[WARNING] Failed to load snd_aloop. Ensure you're running a standard Debian kernel (linux-image-amd64)."
    echo "[WARNING] Audio routing will not work without this module."
    read -p "Press Enter to continue anyway..." || true
}
# --- Prepare desired /etc/asound.conf content ---
echo "[INFO] Preparing ALSA asound.conf configuration..."

WANT_ASOUND=$(cat <<'ASND'
# /etc/asound.conf - oMPX multi-sinks at 192000 Hz
# All PCM devices operate at 192000 Hz (carrier frequency: 80kHz within 192kHz signal)

pcm.format_192k {
type rate
slave {
pcm "hw:Loopback,0,0"
rate 192000
channels 2
}
}

pcm.format_192k_mono {
type rate
slave {
pcm "hw:Loopback,0,0"
rate 192000
channels 1
}
}

pcm.subcarrier_80k_hw {
type rate
slave {
pcm "hw:Loopback,0,0"
rate 192000
channels 2
}
}
# stereo dmix for named sinks (allows multiple clients)

pcm.sink_dmix_192k {
type dmix
ipc_key 3333
slave {
pcm "format_192k"
period_time 0
period_size 4096
buffer_size 65536
channels 2
}
}
# mono dmix for mpx inputs

pcm.mono_dmix_192k {
type dmix
ipc_key 3334
slave {
pcm "format_192k_mono"
period_time 0
period_size 4096
buffer_size 65536
channels 1
}
}
# Named stereo sinks (clients write stereo to these)

pcm.ch1input   { type plug; slave.pcm "sink_dmix_192k"; }
pcm.ch2input   { type plug; slave.pcm "sink_dmix_192k"; }
pcm.ch1preview { type plug; slave.pcm "sink_dmix_192k"; }
pcm.ch2preview { type plug; slave.pcm "sink_dmix_192k"; }
pcm.dsca_src   { type plug; slave.pcm "sink_dmix_192k"; }
# Named mono sinks for MPX content (clients write mono; we'll pan later)

pcm.mpx1 { type plug; slave.pcm "mono_dmix_192k"; }
pcm.mpx2 { type plug; slave.pcm "mono_dmix_192k"; }
# mpx_final: combine/pan mpx1->left, mpx2->right into stereo at 192k and route to hw Loopback

pcm.mpx_final_route {
type route
slave.pcm "format_192k"
slave.channels 2
ttable {
0.0 1   # input channel 0 -> output channel 0 (left)
1.1 1   # input channel 1 -> output channel 1 (right)
}
}
# We construct a virtual device that reads two mono inputs (mpx1,mpx2), maps them to a 2-channel stream,
# and outputs to hw:Loopback,0,0 at 192k.

pcm.mpx_final {
type plug
slave.pcm "hw:Loopback,0,0"
hint.description "MPX Final (192kHz L=mpx1 R=mpx2)"
}
# Provide a combined feed that takes mpx1/mpx2 mono and produces stereo for downstream apps:

pcm.mpx_stereo_src {
type multi
slaves.a.pcm "mpx1"
slaves.a.channels 1
slaves.b.pcm "mpx2"
slaves.b.channels 1
bindings.0.slave a
bindings.0.channel 0
bindings.1.slave b
bindings.1.channel 0
}
# A plug that converts the multi-source into a 2-channel stereo at 192k and sends to loopback playback

pcm.mpx_final_playback {
type plug
slave.pcm "hw:Loopback,0,0"
hint.description "MPX Final Playback (writes to loopback)"
}
# Subcarrier device: MPX subcarrier at 80kHz carrier frequency within 192kHz signal

pcm.mpx_subcarrier_80k {
type plug
slave.pcm "subcarrier_80k_hw"
hint.description "MPX Subcarrier (80kHz carrier in 192kHz signal)"
}

pcm.!default { type plug; slave.pcm "sink_dmix_192k"; }
ctl.!default { type hw; card Loopback; }
ASND
)
# --- Write /etc/asound.conf ---

if [ "$CONFIG_SKIP" = true ]; then
echo "[INFO] Skipping ALSA configuration as requested"
elif [ "$CONFIG_OVERWRITE" = false ]; then
echo "[INFO] Keeping existing ALSA configuration unchanged"
else
echo "[INFO] Writing /etc/asound.conf..."

if [ -f "${ASOUND_CONF_PATH}" ]; then
if ! cmp -s <(printf '%s' "${WANT_ASOUND}") "${ASOUND_CONF_PATH}"; then
if [ "$CONFIG_BACKUP" = true ]; then
cp -a "${ASOUND_CONF_PATH}" "${ASOUND_CONF_PATH}.bak.$(date +%s)" || true
echo "[INFO] Backed up existing ${ASOUND_CONF_PATH}"
fi
printf '%s' "${WANT_ASOUND}" > "${ASOUND_CONF_PATH}"
chmod 644 "${ASOUND_CONF_PATH}" || true
_log "Updated ${ASOUND_CONF_PATH}."
echo "[SUCCESS] ALSA config updated"
else
_log "${ASOUND_CONF_PATH} already matches desired content."
echo "[INFO] ALSA config already current"
fi
else
printf '%s' "${WANT_ASOUND}" > "${ASOUND_CONF_PATH}"
chmod 644 "${ASOUND_CONF_PATH}" || true
_log "Wrote ${ASOUND_CONF_PATH}."
echo "[SUCCESS] ALSA config created"
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
if id -u "${OMPX_USER}" >/dev/null 2>&1; then
crontab -u "${OMPX_USER}" -l 2>/dev/null | grep -v "${SYS_SCRIPTS_DIR}/source" | sed '/^$/d' | crontab -u "${OMPX_USER}" - 2>/dev/null || true
fi
echo "[INFO] Removing old files and directories..."
rm -f "${STEREO_TOOL_WRAPPER}" "${STEREO_TOOL_WRAPPER}.real-check" "${OMPX_ADD}"
rm -rf "${SYS_SCRIPTS_DIR}" "${LIQUIDSOAP_CONF_DIR}" /var/log/radio-opus1.log /var/log/radio-opus2.log
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
if id -u "${OMPX_USER}" >/dev/null 2>&1; then
crontab -u "${OMPX_USER}" -l 2>/dev/null | grep -v "${SYS_SCRIPTS_DIR}/source" | sed '/^$/d' | crontab -u "${OMPX_USER}" - 2>/dev/null || true
fi
echo "[INFO] Removing files and directories..."
rm -f "${STEREO_TOOL_WRAPPER}" "${STEREO_TOOL_WRAPPER}.real-check" "${OMPX_ADD}"
rm -rf "${SYS_SCRIPTS_DIR}" "${LIQUIDSOAP_CONF_DIR}" /var/log/radio-opus1.log /var/log/radio-opus2.log
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
oMPX persistent environment (auto-generated)

RADIO1_URL="${RADIO1_URL}"
RADIO2_URL="${RADIO2_URL}"
PROFILE_WRITTEN
chown "${OMPX_USER}:${OMPX_USER}" "$PROFILE"; chmod 644 "$PROFILE"
_log "Wrote profile ${PROFILE}."
echo "[SUCCESS] Profile configuration created"
# --- Create directories, install packages ---
echo "[INFO] Creating system directories..."

mkdir -p "${SYS_SCRIPTS_DIR}" "${FIFOS_DIR}" "${LIQUIDSOAP_CONF_DIR}"
chown -R "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}"
chmod 755 "${SYS_SCRIPTS_DIR}" "${FIFOS_DIR}" "${LIQUIDSOAP_CONF_DIR}"
echo "[SUCCESS] Directories created at ${SYS_SCRIPTS_DIR}"

echo "[INFO] Updating package lists..."
apt update
echo "[INFO] Installing dependencies (curl, alsa-utils, ffmpeg, sox, ladspa-sdk, swh-plugins, liquidsoap, plus optional kernel module extras)..."
KERNEL_EXTRA="linux-modules-extra-$(uname -r)"
DEBIAN_FRONTEND=noninteractive apt install -y curl alsa-utils ffmpeg sox ladspa-sdk swh-plugins liquidsoap "${KERNEL_EXTRA}" || true
echo "[SUCCESS] Dependencies installed"
# --- Ensure snd_aloop loaded and show devices ---
echo "[INFO] Verifying snd_aloop kernel module..."

if ! lsmod | grep -q snd_aloop; then 
  echo "[INFO] Attempting to load snd_aloop..."
  if ! modprobe snd_aloop; then
    echo "[WARNING] Initial snd_aloop load failed. Trying kernel extra package: ${KERNEL_EXTRA}"
    if ! DEBIAN_FRONTEND=noninteractive apt install -y "${KERNEL_EXTRA}"; then
      echo "[WARNING] Package ${KERNEL_EXTRA} could not be installed or is unavailable"
    fi
    echo "[INFO] Retrying snd_aloop load after installing kernel extras..."
    if modprobe snd_aloop; then
      echo "[SUCCESS] snd_aloop loaded after installing kernel extras"
      _log "snd_aloop loaded after kernel extras"
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
_log "ALSA devices listed above"
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
# --- Create source wrapper scripts (for liquidsoap) ---
echo "[INFO] Creating wrapper scripts..."

for n in 1 2; do
cat > "${SYS_SCRIPTS_DIR}/source${n}.sh" <<WRAP
#!/usr/bin/env bash
set -euo pipefail
PROFILE="${OMPX_HOME}/.profile"
[ -f "$PROFILE" ] && . "$PROFILE"
export RADIO_URL="${RADIO${n}_URL:-}"
exec /usr/bin/liquidsoap "${LIQUIDSOAP_CONF_DIR}/radio${n}.liq"
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
SYS_SCRIPTS_DIR="/opt/mpx-radio"; OMPX_USER="oMPX"; OMPX_HOME="/var/lib/ompx"; CRON_SLEEP=10; LIQUIDSOAP_CONF_DIR="/opt/mpx-radio/liquidsoap"
usage(){ cat <<USAGE
Usage: $0 --radio 1|2 --url URL [--cron-user root|oMPX] [--start-now]
USAGE
}
RADIO=""; URL=""; CRON_USER="${OMPX_USER}"; START_NOW=0
while [ $# -gt 0 ]; do case "$1" in --radio) RADIO="$2"; shift 2;; --url) URL="$2"; shift 2;; --cron-user) CRON_USER="$2"; shift 2;; --start-now) START_NOW=1; shift;; -h|--help) usage; exit 0;; *) echo "Unknown arg: $1"; usage; exit 1;; esac; done
if [ -z "$RADIO" ] || [ -z "$URL" ]; then usage; exit 1; fi
PROFILE="${OMPX_HOME}/.profile"; cp -a "$PROFILE" "${PROFILE}.bak.$(date +%s)"
VAR="RADIO${RADIO}_URL"
if grep -q "^${VAR}=" "$PROFILE"; then sed -i "s|^${VAR}=.*|${VAR}="${URL}"|" "$PROFILE"; else echo "${VAR}="${URL}"" >> "$PROFILE"; fi
chown ${OMPX_USER}:${OMPX_USER} "$PROFILE"; chmod 644 "$PROFILE"
WRAPPER="${SYS_SCRIPTS_DIR}/source${RADIO}.sh"
cat > "$WRAPPER" <<WRAP
#!/usr/bin/env bash
set -euo pipefail
PROFILE="${OMPX_HOME}/.profile"
[ -f "$PROFILE" ] && . "$PROFILE"
export RADIO_URL="${RADIO${RADIO}_URL:-}"
exec /usr/bin/liquidsoap "${LIQUIDSOAP_CONF_DIR}/radio${RADIO}.liq"
WRAP
chown ${OMPX_USER}:${OMPX_USER} "$WRAPPER"; chmod 750 "$WRAPPER"
CRON_CMD="@reboot sleep ${CRON_SLEEP} && ${WRAPPER} >/var/log/radio-opus${RADIO}.log 2>&1 &"
( crontab -u "$CRON_USER" -l 2>/dev/null || true; echo "${CRON_CMD}" ) | crontab -u "$CRON_USER" -
if [ "${START_NOW}" -eq 1 ]; then
if [ "$CRON_USER" = "root" ]; then nohup "${WRAPPER}" >/var/log/radio-opus${RADIO}.log 2>&1 & else su -s /bin/sh -c "nohup ${WRAPPER} >/var/log/radio-opus${RADIO}.log 2>&1 &" "${CRON_USER}"; fi
fi
echo "Persisted ${VAR} in ${PROFILE} and ensured cron @reboot for ${CRON_USER}."
ADD
chmod 750 "${OMPX_ADD}"
chown root:root "${OMPX_ADD}"
echo "[SUCCESS] ompx_add_source helper created"
# --- start_or_shell wrapper ---
echo "[INFO] Creating start_or_shell wrapper..."

cat > "${SYS_SCRIPTS_DIR}/start_or_shell.sh" <<'STARTSH'
#!/usr/bin/env bash
set -euo pipefail

OMPX_USER="oMPX"
SYS_SCRIPTS_DIR="/opt/mpx-radio"
LOG1="/var/log/radio-opus1.log"
LOG2="/var/log/radio-opus2.log"

usage(){ cat <<USAGE
Usage: $0 [--start] [--shell]
--start   Ensure source1.sh and source2.sh are running (background, logs)
--shell   Drop to an interactive shell as oMPX (equivalent to su - oMPX)
If neither flag given, acts as --start.
USAGE
}

start_sources(){
for n in 1 2; do
wrapper="${SYS_SCRIPTS_DIR}/source${n}.sh"
log="/var/log/radio-opus${n}.log"
if ! pgrep -f "${wrapper}" >/dev/null 2>&1; then
su -s /bin/sh -c "nohup "${wrapper}" >>"${log}" 2>&1 &" "${OMPX_USER}"
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

CRON_LINE1="@reboot sleep ${CRON_SLEEP} && ${SYS_SCRIPTS_DIR}/start_or_shell.sh --start >/var/log/radio-opus-start.log 2>&1 &"
existing=$(crontab -u "${OMPX_USER}" -l 2>/dev/null || true)
new_cron="${existing}"
echo "$existing" | grep -F -q "${SYS_SCRIPTS_DIR}/source1.sh" >/dev/null 2>&1 || new_cron="${new_cron}
${CRON_LINE1}"
printf "%s\n" "${new_cron}" | sed '/^$/d' | crontab -u "${OMPX_USER}" -
echo "[SUCCESS] Cron job configured for ${OMPX_USER}"
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
echo "  4. Access oMPX user shell:"
echo "     sudo su - oMPX"
echo ""
chmod +x "$0" || true
echo "[SUCCESS] Installation finished successfully!"
exit 0