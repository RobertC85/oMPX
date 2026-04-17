#!/usr/bin/env bash
set -euo pipefail
PROFILE="/home/ompx/.profile"
[ -f "${PROFILE}" ] && . "${PROFILE}"

# --- oMPX open-source chain: per-program profile/gain support ---
SAMPLE_RATE=192000
PROG1_ALSA_IN="${PROG1_ALSA_IN:-ompx_prg1in_cap}"
PROG2_ALSA_IN="${PROG2_ALSA_IN:-ompx_prg2in_cap}"
PROGRAM2_ENABLED="${PROGRAM2_ENABLED:-false}"
SYS_SCRIPTS_DIR="/opt/mpx-radio"
OMPX_LOG_DIR="/home/ompx/logs"
LOOPBACK_CARD_REF="${LOOPBACK_CARD_REF:-}"
MPX_LEFT_OUT="/tmp/mpx_left_out.pcm"
MPX_RIGHT_OUT="/tmp/mpx_right_out.pcm"
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

# Start ingest wrappers if needed
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

# Clean up and create output FIFOs
for p in "$MPX_LEFT_OUT" "$MPX_RIGHT_OUT" "$MPX_STEREO_FIFO"; do rm -f "$p" || true; mkfifo "$p"; done

# --- Per-program processing using open-source chain ---
MODULES_DIR="/workspaces/oMPX/modules"
MULTIBAND_PROFILE_P1="${MULTIBAND_PROFILE_P1:-${MULTIBAND_PROFILE:-waxdreams2-5band}}"
POST_GAIN_DB_P1="${POST_GAIN_DB_P1:-6}"
MULTIBAND_PROFILE_P2="${MULTIBAND_PROFILE_P2:-${MULTIBAND_PROFILE:-waxdreams2-5band}}"
POST_GAIN_DB_P2="${POST_GAIN_DB_P2:-6}"

# Program 1 processing
(
  ffmpeg -hide_banner -loglevel warning -f alsa -thread_queue_size 10240 -i "${PROG1_ALSA_IN}" -f s16le -ac 2 -ar ${SAMPLE_RATE} - |
  "${MODULES_DIR}/multiband_agc.sh" \
    --profile "${MULTIBAND_PROFILE_P1}" \
    --post-gain-db "${POST_GAIN_DB_P1}" \
    --sample-rate "${SAMPLE_RATE}" \
    --input-format s16le \
    --output-format s16le \
    --channels 2 \
    --dry-run false \
    --show-config false \
  > "$MPX_LEFT_OUT"
) &
FF_PROG1_PID=$!
_log "Started Program 1 open-source chain (profile=${MULTIBAND_PROFILE_P1}, gain=${POST_GAIN_DB_P1}, pid=$FF_PROG1_PID)"

# Program 2 processing (if enabled)
if [ "${PROGRAM2_ENABLED}" = "true" ] && [ -n "${PROG2_ALSA_IN}" ]; then
  (
    ffmpeg -hide_banner -loglevel warning -f alsa -thread_queue_size 10240 -i "${PROG2_ALSA_IN}" -f s16le -ac 2 -ar ${SAMPLE_RATE} - |
    "${MODULES_DIR}/multiband_agc.sh" \
      --profile "${MULTIBAND_PROFILE_P2}" \
      --post-gain-db "${POST_GAIN_DB_P2}" \
      --sample-rate "${SAMPLE_RATE}" \
      --input-format s16le \
      --output-format s16le \
      --channels 2 \
      --dry-run false \
      --show-config false \
    > "$MPX_RIGHT_OUT"
  ) &
  FF_PROG2_PID=$!
  _log "Started Program 2 open-source chain (profile=${MULTIBAND_PROFILE_P2}, gain=${POST_GAIN_DB_P2}, pid=$FF_PROG2_PID)"
else
  # If Program 2 not enabled, inject silence
  ( while :; do dd if=/dev/zero bs=4096 count=256 status=none; sleep 0.1; done ) > "$MPX_RIGHT_OUT" &
  SILENCE_PID=$!
  _log "Program 2 not active/available; injecting silence on right channel"
fi

# Merge processed outputs to stereo FIFO
ffmpeg -hide_banner -loglevel warning \
  -f s16le -ar ${SAMPLE_RATE} -ac 1 -i "$MPX_LEFT_OUT" \
  -f s16le -ar ${SAMPLE_RATE} -ac 1 -i "$MPX_RIGHT_OUT" \
  -filter_complex "[0:a][1:a]join=inputs=2:channel_layout=stereo[aout]" -map "[aout]" \
  -f s16le -ar ${SAMPLE_RATE} -ac 2 - > "$MPX_STEREO_FIFO" &
FF_MERGE_PID=$!
_log "ffmpeg merge pid $FF_MERGE_PID"

# Output to ALSA
ALSA_OUTPUT="${ALSA_OUTPUT:-}"
if [ -z "$ALSA_OUTPUT" ]; then
  if wait_for_alsa_endpoint playback "ompx_prg1mpx" 20; then
    ALSA_OUTPUT="ompx_prg1mpx"
  elif aplay -l 2>/dev/null | grep -qi loopback; then
    ALSA_OUTPUT="hw:${LOOPBACK_CARD_REF},0,0"
  fi
fi
if [ -z "$ALSA_OUTPUT" ]; then _log "No ALSA output selected."; exit 1; fi
ffmpeg -hide_banner -loglevel warning -f s16le -ar ${SAMPLE_RATE} -ac 2 -i "$MPX_STEREO_FIFO" -f alsa "$ALSA_OUTPUT" &
PLAY_PID=$!; _log "MPX playback started (pid ${PLAY_PID:-0})"
wait ${PLAY_PID:-0} || true
kill ${FF_PROG1_PID:-0} ${FF_PROG2_PID:-0} ${SILENCE_PID:-0} ${FF_MERGE_PID:-0} 2>/dev/null || true
_log "run_processing_alsa.sh exiting"
