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
  # If ROLE is already set (from argument or env), use it
  if [ -n "${ROLE:-}" ]; then
    echo "$ROLE"
    return
  fi
  # Only proceed if interactive
  if [ -t 0 ]; then
    if command -v whiptail >/dev/null 2>&1; then
      # whiptail is installed, use it
      ROLE=$(whiptail --title "oMPX Master Installer" --menu "Select which part of the oMPX stack to install:" 20 70 10 \
        "encoding" "Audio encoding/streaming stack" \
        "decoding" "Audio decoding/receiver stack" \
        "processing" "Audio processing/AGC stack" \
        "full" "Full oMPX stack (all roles)" \
        "install" "Interactive install (all steps)" \
        "icecast" "Configure Icecast only" \
        "alsa" "Configure ALSA only" 3>&1 1>&2 2>&3)
      echo "$ROLE"
      return
    else
      # whiptail not installed, ask user what they want
      echo "Whiptail (menu interface) is not installed. How would you like to proceed?"
      echo "  1) Use text prompts (type your answers)"
      echo "  2) Use a menu interface (like whiptail)"
      read -rp "Enter 1 for text prompts, 2 for a menu interface [1]: " PROMPT_CHOICE
      PROMPT_CHOICE=${PROMPT_CHOICE:-1}
      if [ "$PROMPT_CHOICE" = "2" ]; then
        # Try to detect if whiptail is in the package manager
        if command -v apt-get >/dev/null 2>&1 && apt-cache show whiptail >/dev/null 2>&1; then
          echo "[INFO] Adding 'whiptail' to stack dependencies. Please run: sudo apt-get install whiptail"
          exit 1
        elif command -v dnf >/dev/null 2>&1 && dnf info whiptail >/dev/null 2>&1; then
          echo "[INFO] Adding 'newt' (whiptail) to stack dependencies. Please run: sudo dnf install newt"
          exit 1
        elif command -v yum >/dev/null 2>&1 && yum info whiptail >/dev/null 2>&1; then
          echo "[INFO] Adding 'newt' (whiptail) to stack dependencies. Please run: sudo yum install newt"
          exit 1
        elif command -v apk >/dev/null 2>&1 && apk info whiptail >/dev/null 2>&1; then
          echo "[INFO] Adding 'newt' (whiptail) to stack dependencies. Please run: sudo apk add newt"
          exit 1
        else
          echo "[WARN] 'whiptail' is not available in your package manager. Falling back to plain text prompts."
        fi
      fi
      # Fallback to plain text prompt
      read -rp "Which part of the oMPX stack to install? (encoding/decoding/processing/full/install/icecast/alsa): " ROLE
      echo "$ROLE"
      return
    fi
  fi
  # If not interactive, fail with a clear error
  echo "[ERROR] No interactive terminal detected. Please provide the role as a command-line argument (e.g., ./ompx-master-installer.sh encoding)." >&2
  exit 1
}


# --- Main Logic ---
# Accept role as first argument, or fallback to prompt
ROLE="${1:-}"
DISTRO=$(get_distro)
ROLE=$(ROLE="$ROLE" choose_role)
ROLE=$(echo "$ROLE" | tr -d ' \t\n\r')

if [ "$DEBUG" -eq 1 ]; then
  echo "[DEBUG] Detected distro: $DISTRO"
  echo "[DEBUG] Selected role: '$ROLE'"
  echo -n "[DEBUG] ROLE hex: "
  echo -n "$ROLE" | xxd
  ls -l ./encoder/scripts/install.sh
fi

case "$DISTRO" in
  debian|ubuntu|fedora|alpine|tinycore|tce|arch)
    if [ "$DEBUG" -eq 1 ]; then echo "[DEBUG] Entered $DISTRO case"; fi
    case "$ROLE" in
      encoding|processing|full|install)
        if [ "$DEBUG" -eq 1 ]; then echo "[DEBUG] Entered $ROLE role ($DISTRO)"; fi
        ./encoder/scripts/install.sh
        ;;
      icecast)
        ./encoder/scripts/configure_icecast.sh
        ;;
      alsa)
        ./encoder/scripts/configure_alsa.sh
        ;;
      *)
        echo "[ERROR] Selected role '$ROLE' not yet implemented for $DISTRO."
        exit 1
        ;;
    esac
    ;;
  *)
    # Fallback: try to detect Tiny Core by /etc/tc-version
    if [ -f /etc/tc-version ]; then
      echo "[INFO] Tiny Core Linux detected via /etc/tc-version."
      case "$ROLE" in
        encoding|processing|full|install)
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
