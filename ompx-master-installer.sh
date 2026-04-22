#!/usr/bin/env bash
# oMPX Master Installer: Distro/Role Detector
set -euo pipefail

# Debug flag
DEBUG=0
for arg in "$@"; do
  if [ "$arg" = "--debug" ]; then
    DEBUG=1
  fi
done

# --- Detect Linux Distribution ---
get_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$ID"
  else
    echo "unknown"
  fi
}

# --- Prompt for Stack Functionality ---
choose_role() {
  if command -v whiptail >/dev/null 2>&1; then
    ROLE=$(whiptail --title "oMPX Master Installer" --menu "Select which part of the oMPX stack to install:" 20 70 10 \
      "encoding" "Audio encoding/streaming stack" \
      "decoding" "Audio decoding/receiver stack" \
      "processing" "Audio processing/AGC stack" \
      "full" "Full oMPX stack (all roles)" \
      "install" "Interactive install (all steps)" \
      "icecast" "Configure Icecast only" \
      "alsa" "Configure ALSA only" 3>&1 1>&2 2>&3)
  else
    echo "Which part of the oMPX stack to install? (encoding/decoding/processing/full/install/icecast/alsa)"
    read -r ROLE
  fi
  echo "$ROLE"
}

# --- Main Logic ---
DISTRO=$(get_distro)
ROLE=$(choose_role)
ROLE=$(echo "$ROLE" | tr -d ' \t\n\r')

if [ "$DEBUG" -eq 1 ]; then
  echo "[DEBUG] Detected distro: $DISTRO"
  echo "[DEBUG] Selected role: '$ROLE'"
  echo -n "[DEBUG] ROLE hex: "
  echo -n "$ROLE" | xxd
  ls -l ./encoder/scripts/install.sh
fi

case "$DISTRO" in
  debian|ubuntu)
    if [ "$DEBUG" -eq 1 ]; then echo "[DEBUG] Entered debian|ubuntu case"; fi
    case "$ROLE" in
      encoding)
        if [ "$DEBUG" -eq 1 ]; then echo "[DEBUG] Entered encoding role"; fi
        ./encoder/scripts/install.sh
        ;;
      processing)
        if [ "$DEBUG" -eq 1 ]; then echo "[DEBUG] Entered processing role"; fi
        ./encoder/scripts/install.sh
        ;;
      full)
        if [ "$DEBUG" -eq 1 ]; then echo "[DEBUG] Entered full role"; fi
        ./encoder/scripts/install.sh
        ;;
      install)
        if [ "$DEBUG" -eq 1 ]; then echo "[DEBUG] Entered install role"; fi
        ./encoder/scripts/install.sh
        ;;
      icecast)
        if [ "$DEBUG" -eq 1 ]; then echo "[DEBUG] Entered icecast role"; fi
        ./encoder/scripts/configure_icecast.sh
        ;;
      alsa)
        if [ "$DEBUG" -eq 1 ]; then echo "[DEBUG] Entered alsa role"; fi
        ./encoder/scripts/configure_alsa.sh
        ;;
      *)
        echo "[ERROR] Selected role '$ROLE' not yet implemented for $DISTRO."
        exit 1
        ;;
    esac
    ;;
  fedora)
    echo "[INFO] Fedora detected."
    case "$ROLE" in
      encoding|full|install)
        ./encoder/scripts/install.sh
        ;;
      icecast)
        ./encoder/scripts/configure_icecast.sh
        ;;
      alsa)
        ./encoder/scripts/configure_alsa.sh
        ;;
      *)
        echo "[ERROR] Selected role '$ROLE' not yet implemented for Fedora."
        exit 1
        ;;
    esac
    ;;
  alpine)
    echo "[INFO] Alpine Linux detected."
    case "$ROLE" in
      encoding|full|install)
        ./encoder/scripts/install.sh
        ;;
      icecast)
        ./encoder/scripts/configure_icecast.sh
        ;;
      alsa)
        ./encoder/scripts/configure_alsa.sh
        ;;
      *)
        echo "[ERROR] Selected role '$ROLE' not yet implemented for Alpine."
        exit 1
        ;;
    esac
    ;;
  tinycore|tce)
    echo "[INFO] Tiny Core Linux detected."
    case "$ROLE" in
      encoding|full|install)
        ./encoder/scripts/install.sh
        ;;
      icecast)
        ./encoder/scripts/configure_icecast.sh
        ;;
      alsa)
        ./encoder/scripts/configure_alsa.sh
        ;;
      *)
        echo "[ERROR] Selected role '$ROLE' not yet implemented for Tiny Core."
        exit 1
        ;;
    esac
    ;;
  arch)
    echo "[INFO] Arch Linux detected."
    case "$ROLE" in
      encoding|full|install)
        ./encoder/scripts/install.sh
        ;;
      icecast)
        ./encoder/scripts/configure_icecast.sh
        ;;
      alsa)
        ./encoder/scripts/configure_alsa.sh
        ;;
      *)
        echo "[ERROR] Selected role '$ROLE' not yet implemented for Arch."
        exit 1
        ;;
    esac
    ;;
  *)
    # Fallback: try to detect Tiny Core by /etc/tc-version
    if [ -f /etc/tc-version ]; then
      echo "[INFO] Tiny Core Linux detected via /etc/tc-version."
      case "$ROLE" in
        encoding|full|install)
          ./encoder/scripts/install.sh
          ;;
        icecast)
          ./encoder/scripts/configure_icecast.sh
          ;;
        alsa)
          ./encoder/scripts/configure_alsa.sh
          ;;
        *)
          echo "[ERROR] Selected role '$ROLE' not yet implemented for Tiny Core."
          exit 1
          ;;
      esac
    else
      echo "[ERROR] Unsupported or undetected Linux distribution: $DISTRO"
      exit 1
    fi
    ;;
esac
