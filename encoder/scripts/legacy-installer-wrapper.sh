#!/usr/bin/env bash
# Wrapper for legacy oMPX-Encoder-Debian-setup.sh to run from scripts dir
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LEGACY_ROOT="$SCRIPT_DIR/.."

cd "$LEGACY_ROOT"
bash ./oMPX-Encoder-Debian-setup.sh "$@"
