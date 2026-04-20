#!/usr/bin/env bash
set -euo pipefail

# Multiband compressor + AGC module for oMPX plumbing.
# Default profile is a lean 5-band approximation inspired by a Stereo Tool preset.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="${PROFILE_DIR:-${SCRIPT_DIR}/profiles}"

INPUT_URL="${INPUT_URL:-default}"
OUTPUT_URL="${OUTPUT_URL:-default}"
INPUT_FORMAT="${INPUT_FORMAT:-alsa}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-alsa}"
SAMPLE_RATE="${SAMPLE_RATE:-48000}"
CHANNELS="${CHANNELS:-2}"
PROFILE="${PROFILE:-waxdreams2-5band}"
DRY_RUN="false"
SHOW_CONFIG="false"
PRE_GAIN_DB="${PRE_GAIN_DB:-0}"
POST_GAIN_DB="${POST_GAIN_DB:-0}"
PARALLEL_DRY_MIX="${PARALLEL_DRY_MIX:-0}"
STEREO_WIDTH="${STEREO_WIDTH:-1.0}"
HF_TAME_DB="${HF_TAME_DB:-0}"
HF_TAME_FREQ="${HF_TAME_FREQ:-7000}"

# 5-band crossover frequencies in Hz.
XOVER_1="${XOVER_1:-90}"
XOVER_2="${XOVER_2:-280}"
XOVER_3="${XOVER_3:-900}"
XOVER_4="${XOVER_4:-2800}"

# Per-band companders.
BAND1_COMPAND="${BAND1_COMPAND:-attacks=0.0018:decays=0.006:points=-80/-80|-30/-30|-18/-10|0/-5}"
BAND2_COMPAND="${BAND2_COMPAND:-attacks=0.0012:decays=0.005:points=-80/-80|-30/-30|-16/-9|0/-4.5}"
BAND3_COMPAND="${BAND3_COMPAND:-attacks=0.0009:decays=0.004:points=-80/-80|-28/-28|-14/-8|0/-4}"
BAND4_COMPAND="${BAND4_COMPAND:-attacks=0.0007:decays=0.003:points=-80/-80|-26/-26|-12/-7|0/-3.5}"
BAND5_COMPAND="${BAND5_COMPAND:-attacks=0.0006:decays=0.003:points=-80/-80|-24/-24|-10/-6|0/-3}"
BAND1_TRIM_DB="${BAND1_TRIM_DB:-0}"
BAND2_TRIM_DB="${BAND2_TRIM_DB:-0}"
BAND3_TRIM_DB="${BAND3_TRIM_DB:-0}"
BAND4_TRIM_DB="${BAND4_TRIM_DB:-0}"
BAND5_TRIM_DB="${BAND5_TRIM_DB:-0}"

# AGC and output protection.
AGC_FILTER="${AGC_FILTER:-dynaudnorm=f=250:g=7:m=15:p=0.95}"
OUTPUT_LIMIT="${OUTPUT_LIMIT:-0.96}"
HPF_FREQ="${HPF_FREQ:-30}"
LPF_FREQ="${LPF_FREQ:-15000}"


#!/usr/bin/env bash
# oMPX Multiband AGC/Compressor Module
# ------------------------------------
# Standalone FFmpeg-based processing module for oMPX.
# Features:
#   - 5-band compression (Stereo Tool-inspired default)
#   - Wideband AGC (dynaudnorm)
#   - Output limiter protection
#   - Output filter shaping (high-pass and low-pass)
#   - Dry/wet parallel blend
#   - Stereo width control
#   - Per-band trim controls
#   - Profile system for easy tuning (see profiles/)
#
# Usage:
#   ./multiband_agc.sh --input-url ... --output-url ... [options]
#
# For more info, see: https://github.com/RobertC85/oMPX

set -euo pipefail

# Script and profile directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="${PROFILE_DIR:-${SCRIPT_DIR}/profiles}"

# Input/output configuration
INPUT_URL="${INPUT_URL:-default}"
OUTPUT_URL="${OUTPUT_URL:-default}"
INPUT_FORMAT="${INPUT_FORMAT:-alsa}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-alsa}"
SAMPLE_RATE="${SAMPLE_RATE:-48000}"
CHANNELS="${CHANNELS:-2}"
PROFILE="${PROFILE:-waxdreams2-5band}"
DRY_RUN="false"
SHOW_CONFIG="false"
PRE_GAIN_DB="${PRE_GAIN_DB:-0}"
POST_GAIN_DB="${POST_GAIN_DB:-0}"
PARALLEL_DRY_MIX="${PARALLEL_DRY_MIX:-0}"
STEREO_WIDTH="${STEREO_WIDTH:-1.0}"
HF_TAME_DB="${HF_TAME_DB:-0}"
HF_TAME_FREQ="${HF_TAME_FREQ:-7000}"

# 5-band crossover frequencies in Hz
XOVER_1="${XOVER_1:-90}"
XOVER_2="${XOVER_2:-280}"
XOVER_3="${XOVER_3:-900}"
XOVER_4="${XOVER_4:-2800}"

# Per-band compander settings
BAND1_COMPAND="${BAND1_COMPAND:-attacks=0.0018:decays=0.006:points=-80/-80|-30/-30|-18/-10|0/-5}"
BAND2_COMPAND="${BAND2_COMPAND:-attacks=0.0012:decays=0.005:points=-80/-80|-30/-30|-16/-9|0/-4.5}"
BAND3_COMPAND="${BAND3_COMPAND:-attacks=0.0009:decays=0.004:points=-80/-80|-28/-28|-14/-8|0/-4}"
BAND4_COMPAND="${BAND4_COMPAND:-attacks=0.0007:decays=0.003:points=-80/-80|-26/-26|-12/-7|0/-3.5}"
BAND5_COMPAND="${BAND5_COMPAND:-attacks=0.0006:decays=0.003:points=-80/-80|-24/-24|-10/-6|0/-3}"
BAND1_TRIM_DB="${BAND1_TRIM_DB:-0}"
BAND2_TRIM_DB="${BAND2_TRIM_DB:-0}"
BAND3_TRIM_DB="${BAND3_TRIM_DB:-0}"
BAND4_TRIM_DB="${BAND4_TRIM_DB:-0}"
BAND5_TRIM_DB="${BAND5_TRIM_DB:-0}"

# AGC and output protection
AGC_FILTER="${AGC_FILTER:-dynaudnorm=f=250:g=7:m=15:p=0.95}"
OUTPUT_LIMIT="${OUTPUT_LIMIT:-0.96}"
HPF_FREQ="${HPF_FREQ:-30}"
LPF_FREQ="${LPF_FREQ:-15000}"

# Validate profile name (safe for file loading)
      BAND1_COMPAND='attacks=0.003:decays=0.25:points=-80/-80|-24/-24|-12/-8|0/-4'
      BAND2_COMPAND='attacks=0.0025:decays=0.2:points=-80/-80|-24/-24|-11/-7|0/-3.5'
      BAND3_COMPAND='attacks=0.002:decays=0.18:points=-80/-80|-24/-24|-10/-7|0/-3'

# Apply built-in profile settings (expand as needed)
apply_builtin_profile() {
  local profile_name="$1"
  case "${profile_name}" in
    waxdreams2-5band)
      :
      ;;
    waxdreams2-safe)
      BAND4_COMPAND='attacks=0.0018:decays=0.16:points=-80/-80|-24/-24|-10/-6.5|0/-2.8'
      BAND5_COMPAND='attacks=0.0015:decays=0.15:points=-80/-80|-24/-24|-9/-6|0/-2.5'
      AGC_FILTER='dynaudnorm=f=150:g=12:m=9:p=0.9'
      OUTPUT_LIMIT=0.98
      HPF_FREQ=20
      LPF_FREQ=18000
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

apply_external_profile() {
  local profile_name="$1"
  local depth="${2:-0}"
  local profile_file=""
  local base_profile=""
  [ "${depth}" -le 8 ] || { echo "Profile inheritance depth exceeded for ${profile_name}" >&2; return 1; }
  is_safe_profile_name "${profile_name}" || return 1
  profile_file="${PROFILE_DIR}/${profile_name}.env"
  [ -r "${profile_file}" ] || return 1
  # First pass: load profile to inspect optional BASE_PROFILE.
  # shellcheck source=/dev/null
  . "${profile_file}"
  base_profile="${BASE_PROFILE:-}"
  if [ -n "${base_profile}" ] && [ "${base_profile}" != "${profile_name}" ]; then
    BASE_PROFILE=""
    apply_profile_name "${base_profile}" "$((depth + 1))" || return 1
    # Second pass: apply current profile overrides on top of base profile.
    # shellcheck source=/dev/null
    . "${profile_file}"
  fi
  BASE_PROFILE=""
  return 0
}

apply_profile_name() {
  local profile_name="$1"
  local depth="${2:-0}"
  if apply_external_profile "${profile_name}" "${depth}"; then
    PROFILE_SOURCE="file:${PROFILE_DIR}/${profile_name}.env"
    return 0
  fi
  if apply_builtin_profile "${profile_name}"; then
    PROFILE_SOURCE="builtin:${profile_name}"
    return 0
  fi
  return 1
}

apply_profile() {
  if apply_profile_name "${PROFILE}" 0; then
    return 0
  fi
  echo "Unknown profile: ${PROFILE}" >&2
  echo "Use --list-profiles to see built-ins and external profiles in ${PROFILE_DIR}" >&2
  exit 1
}

print_effective_config() {
  cat <<EOF
PROFILE=${PROFILE}
PROFILE_SOURCE=${PROFILE_SOURCE}
INPUT_FORMAT=${INPUT_FORMAT}
OUTPUT_FORMAT=${OUTPUT_FORMAT}
SAMPLE_RATE=${SAMPLE_RATE}
CHANNELS=${CHANNELS}
XOVER_1=${XOVER_1}
XOVER_2=${XOVER_2}
XOVER_3=${XOVER_3}
XOVER_4=${XOVER_4}
PRE_GAIN_DB=${PRE_GAIN_DB}
POST_GAIN_DB=${POST_GAIN_DB}
PARALLEL_DRY_MIX=${PARALLEL_DRY_MIX}
STEREO_WIDTH=${STEREO_WIDTH}
HPF_FREQ=${HPF_FREQ}
LPF_FREQ=${LPF_FREQ}
HF_TAME_DB=${HF_TAME_DB}
HF_TAME_FREQ=${HF_TAME_FREQ}
OUTPUT_LIMIT=${OUTPUT_LIMIT}
AGC_FILTER=${AGC_FILTER}
BAND1_TRIM_DB=${BAND1_TRIM_DB}
BAND2_TRIM_DB=${BAND2_TRIM_DB}
BAND3_TRIM_DB=${BAND3_TRIM_DB}
BAND4_TRIM_DB=${BAND4_TRIM_DB}
BAND5_TRIM_DB=${BAND5_TRIM_DB}
EOF
}

print_ffmpeg_cmd() {
  cat <<EOF
ffmpeg -hide_banner -loglevel warning -nostdin -thread_queue_size 16384 -f "${INPUT_FORMAT}" -ac "${CHANNELS}" -ar "${SAMPLE_RATE}" -i "${INPUT_URL}" -filter_complex "${audio_graph}" -map "[out]" -ac "${CHANNELS}" -ar "${SAMPLE_RATE}" -f "${OUTPUT_FORMAT}" "${OUTPUT_URL}"
EOF
}

print_profiles() {
  echo "Built-in profiles:"
  cat <<'EOF'
waxdreams2-5band : fast 5-band profile inspired by uploaded Stereo Tool settings
waxdreams2-safe  : gentler version of waxdreams2 for longer-listen cleanliness
fm-loud          : denser and punchier FM-style profile
voice-safe       : speech-priority profile with reduced harshness
classic-3band    : softer legacy-compatible profile
EOF
  if [ -d "${PROFILE_DIR}" ]; then
    echo ""
    echo "External profiles (${PROFILE_DIR}):"
    find "${PROFILE_DIR}" -maxdepth 1 -type f -name '*.env' -printf '%f\n' 2>/dev/null | sed 's/\.env$//' | sort | sed 's/^/  /' || true
  fi
}

is_number() {
  [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

usage() {
  cat <<'EOF'
Usage:
  multiband_agc.sh [options]

Options:
  --input-url URL           Input URL/device (default: default)
  --output-url URL          Output URL/device (default: default)
  --input-format FORMAT     ffmpeg input format (default: alsa)
  --output-format FORMAT    ffmpeg output format (default: alsa)
  --profile NAME            Processing profile name
  --profile-dir PATH        Directory containing external profile .env files
  --list-profiles           Print available profiles and exit
  --show-config             Print resolved configuration and exit
  --dry-run                 Print generated ffmpeg command and exit
  --sample-rate HZ          Processing sample rate (default: 48000)
  --channels N              Channel count (default: 2)
  --pre-gain-db DB          Input gain before processing (default: 0)
  --post-gain-db DB         Output gain after limiter (default: 0)
  --parallel-dry MIX        Dry signal mix 0.0..1.0 (default: 0)
  --stereo-width VALUE      Stereo width multiplier for extrastereo (default: 1.0)
  --x1 HZ                   Crossover 1 (low -> low-mid)
  --x2 HZ                   Crossover 2 (low-mid -> mid)
  --x3 HZ                   Crossover 3 (mid -> high-mid)
  --x4 HZ                   Crossover 4 (high-mid -> high)
  --band1-trim-db DB        Band 1 trim in dB (default: 0)
  --band2-trim-db DB        Band 2 trim in dB (default: 0)
  --band3-trim-db DB        Band 3 trim in dB (default: 0)
  --band4-trim-db DB        Band 4 trim in dB (default: 0)
  --band5-trim-db DB        Band 5 trim in dB (default: 0)
  --hpf HZ                  Final high-pass filter frequency (default: 30)
  --lpf HZ                  Final low-pass filter frequency (default: 15000)
  --hf-tame-db DB           High shelf cut amount in dB (default: 0)
  --hf-tame-freq HZ         High shelf cutoff for hf tame (default: 7000)
  --agc-filter FILTER       ffmpeg AGC filter (default: dynaudnorm...)
  --output-limit VALUE      Limiter ceiling 0.0-1.0 (default: 0.98)
  --help                    Show this help

Examples:
  INPUT_URL=ompx_prg1in_cap OUTPUT_URL=ompx_prg1in ./multiband_agc.sh
  ./multiband_agc.sh --profile waxdreams2-5band --input-url hw:Loopback,10,1 --output-url hw:Loopback,10,0 --sample-rate 192000
EOF
}

apply_profile

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-url) INPUT_URL="$2"; shift 2 ;;
    --output-url) OUTPUT_URL="$2"; shift 2 ;;
    --input-format) INPUT_FORMAT="$2"; shift 2 ;;
    --output-format) OUTPUT_FORMAT="$2"; shift 2 ;;
    --profile-dir) PROFILE_DIR="$2"; shift 2 ;;
    --list-profiles) print_profiles; exit 0 ;;
    --show-config) SHOW_CONFIG="true"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --profile) PROFILE="$2"; apply_profile; shift 2 ;;
    --sample-rate) SAMPLE_RATE="$2"; shift 2 ;;
    --channels) CHANNELS="$2"; shift 2 ;;
    --pre-gain-db) PRE_GAIN_DB="$2"; shift 2 ;;
    --post-gain-db) POST_GAIN_DB="$2"; shift 2 ;;
    --parallel-dry) PARALLEL_DRY_MIX="$2"; shift 2 ;;
    --stereo-width) STEREO_WIDTH="$2"; shift 2 ;;
    --x1) XOVER_1="$2"; shift 2 ;;
    --x2) XOVER_2="$2"; shift 2 ;;
    --x3) XOVER_3="$2"; shift 2 ;;
    --x4) XOVER_4="$2"; shift 2 ;;
    --band1-trim-db) BAND1_TRIM_DB="$2"; shift 2 ;;
    --band2-trim-db) BAND2_TRIM_DB="$2"; shift 2 ;;
    --band3-trim-db) BAND3_TRIM_DB="$2"; shift 2 ;;
    --band4-trim-db) BAND4_TRIM_DB="$2"; shift 2 ;;
    --band5-trim-db) BAND5_TRIM_DB="$2"; shift 2 ;;
    # Backward compatibility with previous 3-band flags.
    --xover-low-mid) XOVER_2="$2"; shift 2 ;;
    --xover-mid-high) XOVER_4="$2"; shift 2 ;;
    --hpf) HPF_FREQ="$2"; shift 2 ;;
    --lpf) LPF_FREQ="$2"; shift 2 ;;
    --hf-tame-db) HF_TAME_DB="$2"; shift 2 ;;
    --hf-tame-freq) HF_TAME_FREQ="$2"; shift 2 ;;
    --agc-filter) AGC_FILTER="$2"; shift 2 ;;
    --output-limit) OUTPUT_LIMIT="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! [[ "$SAMPLE_RATE" =~ ^[0-9]+$ ]]; then
  echo "Invalid sample rate: $SAMPLE_RATE" >&2
  exit 1
fi
if ! [[ "$CHANNELS" =~ ^[0-9]+$ ]]; then
  echo "Invalid channel count: $CHANNELS" >&2
  exit 1
fi
if ! is_number "$PRE_GAIN_DB" || ! is_number "$POST_GAIN_DB" || ! is_number "$PARALLEL_DRY_MIX" || ! is_number "$STEREO_WIDTH" || ! is_number "$HF_TAME_DB"; then
  echo "Invalid numeric option (pre/post gain, parallel dry, stereo width, or hf tame)" >&2
  exit 1
fi
if ! is_number "$BAND1_TRIM_DB" || ! is_number "$BAND2_TRIM_DB" || ! is_number "$BAND3_TRIM_DB" || ! is_number "$BAND4_TRIM_DB" || ! is_number "$BAND5_TRIM_DB"; then
  echo "Invalid band trim value; expected numeric dB values" >&2
  exit 1
fi
if ! [[ "$XOVER_1" =~ ^[0-9]+$ ]] || ! [[ "$XOVER_2" =~ ^[0-9]+$ ]] || ! [[ "$XOVER_3" =~ ^[0-9]+$ ]] || ! [[ "$XOVER_4" =~ ^[0-9]+$ ]]; then
  echo "Crossovers must be integer Hz values" >&2
  exit 1
fi
if ! [[ "$HPF_FREQ" =~ ^[0-9]+$ ]] || ! [[ "$LPF_FREQ" =~ ^[0-9]+$ ]] || ! [[ "$HF_TAME_FREQ" =~ ^[0-9]+$ ]]; then
  echo "HPF/LPF frequencies must be integer Hz values" >&2
  exit 1
fi
if awk -v d="$PARALLEL_DRY_MIX" 'BEGIN { exit !(d >= 0 && d <= 1) }'; then :; else
  echo "parallel-dry must be between 0.0 and 1.0" >&2
  exit 1
fi
if awk -v l="$OUTPUT_LIMIT" 'BEGIN { exit !(l > 0 && l <= 1) }'; then :; else
  echo "output-limit must be within (0, 1]" >&2
  exit 1
fi
if (( XOVER_1 >= XOVER_2 || XOVER_2 >= XOVER_3 || XOVER_3 >= XOVER_4 )); then
  echo "Crossovers must be strictly increasing: x1 < x2 < x3 < x4" >&2
  exit 1
fi
if (( HPF_FREQ >= LPF_FREQ )); then
  echo "hpf must be lower than lpf" >&2
  exit 1
fi

echo "[multiband-agc] profile=${PROFILE} source=${PROFILE_SOURCE:-unknown} in=${INPUT_FORMAT}:${INPUT_URL} out=${OUTPUT_FORMAT}:${OUTPUT_URL} sr=${SAMPLE_RATE} ch=${CHANNELS}"

WET_MIX=$(awk -v d="${PARALLEL_DRY_MIX}" 'BEGIN { w = 1.0 - d; if (w < 0) w = 0; printf "%.6f", w }')

HF_TAME_FILTER="anull"
if awk -v d="${HF_TAME_DB}" 'BEGIN { exit !(d != 0) }'; then
  HF_TAME_FILTER="highshelf=f=${HF_TAME_FREQ}:g=${HF_TAME_DB}"
fi

audio_graph="[0:a]aresample=${SAMPLE_RATE},aformat=sample_fmts=fltp,volume=${PRE_GAIN_DB}dB,asplit=6[dry][b1][b2][b3][b4][b5]; \
[b1]lowpass=f=${XOVER_1},compand=${BAND1_COMPAND},volume=${BAND1_TRIM_DB}dB[b1c]; \
[b2]highpass=f=${XOVER_1},lowpass=f=${XOVER_2},compand=${BAND2_COMPAND},volume=${BAND2_TRIM_DB}dB[b2c]; \
[b3]highpass=f=${XOVER_2},lowpass=f=${XOVER_3},compand=${BAND3_COMPAND},volume=${BAND3_TRIM_DB}dB[b3c]; \
[b4]highpass=f=${XOVER_3},lowpass=f=${XOVER_4},compand=${BAND4_COMPAND},volume=${BAND4_TRIM_DB}dB[b4c]; \
[b5]highpass=f=${XOVER_4},compand=${BAND5_COMPAND},volume=${BAND5_TRIM_DB}dB[b5c]; \
[b1c][b2c][b3c][b4c][b5c]amix=inputs=5:normalize=0,${AGC_FILTER},highpass=f=${HPF_FREQ},lowpass=f=${LPF_FREQ},${HF_TAME_FILTER},alimiter=limit=${OUTPUT_LIMIT}[wet]; \
[wet][dry]amix=inputs=2:weights='${WET_MIX} ${PARALLEL_DRY_MIX}':normalize=0,extrastereo=m=${STEREO_WIDTH},volume=${POST_GAIN_DB}dB[out]"

if [ "${SHOW_CONFIG}" = "true" ]; then
  print_effective_config
  [ "${DRY_RUN}" = "true" ] || exit 0
fi

if [ "${DRY_RUN}" = "true" ]; then
  print_ffmpeg_cmd
  exit 0
fi

exec ffmpeg -hide_banner -loglevel warning -nostdin \
  -thread_queue_size 16384 \
  -f "${INPUT_FORMAT}" -ac "${CHANNELS}" -ar "${SAMPLE_RATE}" -i "${INPUT_URL}" \
  -filter_complex "${audio_graph}" \
  -map "[out]" -ac "${CHANNELS}" -ar "${SAMPLE_RATE}" \
  -f "${OUTPUT_FORMAT}" "${OUTPUT_URL}"
