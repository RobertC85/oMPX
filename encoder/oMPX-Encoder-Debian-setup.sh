#!/usr/bin/env bash
set -euo pipefail
# oMPX unified installer + ALSA asound.conf setup (192kHz / 80kHz subcarrier)
# Date: 2026-04-07
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
# --- Ensure snd_aloop loads and write modprobe options ---

cat > /etc/modules-load.d/snd-aloop.conf <<'EOF'
snd-aloop
EOF
cat > /etc/modprobe.d/snd-aloop.conf <<'EOF'
options snd-aloop pcm_substreams=16
EOF
modprobe snd_aloop || true
# --- Prepare desired /etc/asound.conf content ---

read -r -d '' WANT_ASOUND <<'ASND'
# /etc/asound.conf - oMPX multi-sinks at 192000 Hz + 80kHz subcarrier
# All PCM devices operate at 192000 Hz unless noted (subcarrier at 80000 Hz)

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
rate 80000
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
# Subcarrier device: resample MPX final to 80000 Hz for the Opus subcarrier

pcm.mpx_subcarrier_80k {
type plug
slave.pcm "subcarrier_80k_hw"
hint.description "MPX Subcarrier (80kHz resampled)"
}

pcm.!default { type plug; slave.pcm "sink_dmix_192k"; }
ctl.!default { type hw; card Loopback; }
ASND
# --- Write /etc/asound.conf only if different (backup existing) ---

if [ -f "${ASOUND_CONF_PATH}" ]; then
if ! cmp -s <(printf '%s' "${WANT_ASOUND}") "${ASOUND_CONF_PATH}"; then
cp -a "${ASOUND_CONF_PATH}" "${ASOUND_CONF_PATH}.bak.$(date +%s)" || true
printf '%s' "${WANT_ASOUND}" > "${ASOUND_CONF_PATH}"
chmod 644 "${ASOUND_CONF_PATH}" || true
_log "Updated ${ASOUND_CONF_PATH} (backup saved)."
else
_log "${ASOUND_CONF_PATH} already matches desired content."
fi
else
printf '%s' "${WANT_ASOUND}" > "${ASOUND_CONF_PATH}"
chmod 644 "${ASOUND_CONF_PATH}" || true
_log "Wrote ${ASOUND_CONF_PATH}."
fi
# --- Check existing installation ---

found=0
msg=""
if id -u "${OMPX_USER}" >/dev/null 2>&1; then found=1; msg="${msg}user:${OMPX_USER} "; fi
if [ -d "${SYS_SCRIPTS_DIR}" ]; then found=1; msg="${msg}${SYS_SCRIPTS_DIR} "; fi
if systemctl list-unit-files | grep -q '^mpx-processing-alsa.service'; then found=1; msg="${msg}mpx-processing-alsa.service "; fi

if [ "$found" -eq 1 ]; then
echo "Existing oMPX installation detected (${msg}). Choose action:"
echo "  K) Keep existing (overwrite generated files only)"
echo "  R) Reinstall (clean -> fresh install)  *recommended for broken installs*"
echo "  A) Abort (do nothing)"
read -t 30 -p "Select [K/R/A] (default A): " choice || choice="A"
choice=${choice^^}
case "$choice" in
R)
echo "Performing full cleanup before reinstall..."
systemctl stop mpx-processing-alsa.service mpx-watchdog.service 2>/dev/null || true
systemctl disable mpx-processing-alsa.service mpx-watchdog.service 2>/dev/null || true
rm -f "${SYSTEMD_DIR}/mpx-processing-alsa.service" "${SYSTEMD_DIR}/mpx-watchdog.service"
systemctl daemon-reload || true
if id -u "${OMPX_USER}" >/dev/null 2>&1; then
crontab -u "${OMPX_USER}" -l 2>/dev/null | grep -v "${SYS_SCRIPTS_DIR}/source" | sed '/^$/d' | crontab -u "${OMPX_USER}" - 2>/dev/null || true
fi
rm -f "${STEREO_TOOL_WRAPPER}" "${STEREO_TOOL_WRAPPER}.real-check" "${OMPX_ADD}"
rm -rf "${SYS_SCRIPTS_DIR}" "${LIQUIDSOAP_CONF_DIR}" /var/log/radio-opus1.log /var/log/radio-opus2.log
rm -f "${OMPX_HOME}/.profile" "${OMPX_HOME}/.profile".bak.* || true
if id -u "${OMPX_USER}" >/dev/null 2>&1; then userdel -r "${OMPX_USER}" || true; fi
modprobe -r snd_aloop 2>/dev/null || true
;;
K)
echo "Keeping existing installation; generated files will be overwritten."
;;
*)
echo "Aborting."; exit 0;;
esac
fi
# --- Create system user if missing (with interactive shell) ---

if ! id -u "${OMPX_USER}" >/dev/null 2>&1; then
useradd --system --home "${OMPX_HOME}" --create-home --shell "${OMPX_SHELL}" --comment "oMPX service account" "${OMPX_USER}"
else
_log "User ${OMPX_USER} exists; ensuring shell is ${OMPX_SHELL}."
usermod -s "${OMPX_SHELL}" "${OMPX_USER}" || true
fi
# --- Write profile (overwrite) ---

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
# --- Create directories, install packages ---

mkdir -p "${SYS_SCRIPTS_DIR}" "${FIFOS_DIR}" "${LIQUIDSOAP_CONF_DIR}"
chown -R "${OMPX_USER}:${OMPX_USER}" "${SYS_SCRIPTS_DIR}"
chmod 755 "${SYS_SCRIPTS_DIR}" "${FIFOS_DIR}" "${LIQUIDSOAP_CONF_DIR}"
apt update
DEBIAN_FRONTEND=noninteractive apt install -y curl alsa-utils alsa-modules-$(uname -r) ffmpeg sox ladspa-sdk swh-plugins liquidsoap || true
# --- Ensure snd_aloop loaded and show devices ---

if ! lsmod | grep -q snd_aloop; then modprobe snd_aloop || true; else _log "snd_aloop loaded"; fi
sleep 1; _log "ALSA devices:"; aplay -l 2>/dev/null || true
# --- Create FIFOs for liquidsoap outputs ---

for r in 1 2; do
fifo="${FIFOS_DIR}/radio${r}.pcm"
rm -f "$fifo" || true
mkfifo -m 660 "$fifo"
chown "${OMPX_USER}:${OMPX_USER}" "$fifo"
done
# --- Liquidsoap configuration files (safe templates) ---

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
# --- Create source wrapper scripts (for liquidsoap) ---

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
done
# --- Processing script: run_processing_alsa_liquid.sh ---

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
# --- systemd units ---

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
# --- stereo-tool wrapper & checker ---

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
# --- ompx_add_source helper (persist radio URL, create wrapper, setup cron) ---

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
# --- start_or_shell wrapper ---

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
# --- Install @reboot cron for oMPX to start sources at boot ---

CRON_LINE1="@reboot sleep ${CRON_SLEEP} && ${SYS_SCRIPTS_DIR}/start_or_shell.sh --start >/var/log/radio-opus-start.log 2>&1 &"
existing=$(crontab -u "${OMPX_USER}" -l 2>/dev/null || true)
new_cron="${existing}"
echo "$existing" | grep -F -q "${SYS_SCRIPTS_DIR}/source1.sh" >/dev/null 2>&1 || new_cron="${new_cron}
${CRON_LINE1}"
printf "%s\n" "${new_cron}" | sed '/^$/d' | crontab -u "${OMPX_USER}" -
# --- Enable and start services ---

systemctl daemon-reload
systemctl enable --now mpx-processing-alsa.service mpx-watchdog.service || true

_log "Install complete. Profile: ${PROFILE}"
echo "Use ${OMPX_ADD} --radio 1 --url 'https://your.stream/url' --cron-user oMPX --start-now"
exit 0