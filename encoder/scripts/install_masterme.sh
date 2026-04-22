MASTERME_WEB_PORT="${MASTERME_WEB_PORT:-8082}"

# ...existing logic...

# Launch the web UI after install (background)
if command -v python3 >/dev/null 2>&1; then
	nohup env MASTERME_WEB_PORT="$MASTERME_WEB_PORT" python3 "$SCRIPT_DIR/masterme_web_ui.py" &
	whiptail --title "MasterMe Web UI" --msgbox "MasterMe Web UI started on port $MASTERME_WEB_PORT.\nOpen http://localhost:$MASTERME_WEB_PORT in your browser." 10 70
else
	whiptail --title "MasterMe Web UI" --msgbox "Python3 not found. Cannot start MasterMe Web UI." 8 60
fi
#!/usr/bin/env bash
# Install MasterMe audio processor (placeholder logic)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"


# Detect CPU architecture
ARCH=$(uname -m)
ARCH_MSG="($ARCH)"


# Download and build MasterMe from git
MME_GIT_URL="https://github.com/trummerschlunk/master_me.git"
MME_DIR="$HOME/master_me_build"
MME_SRC_DIR="$MME_DIR/master_me"
MME_BIN="$HOME/.local/bin/master_me"

mkdir -p "$MME_DIR"
cd "$MME_DIR"


if [ ! -d "$MME_SRC_DIR" ]; then
	whiptail --title "MasterMe Installer" --msgbox "Cloning MasterMe source from GitHub..." 8 60
	git clone "$MME_GIT_URL" "$MME_SRC_DIR"
	cd "$MME_SRC_DIR"
	git submodule update --init --recursive
	cd "$MME_DIR"
else
	whiptail --title "MasterMe Installer" --msgbox "MasterMe source already cloned. Pulling latest changes..." 8 60
	cd "$MME_SRC_DIR"
	git pull
	git submodule update --init --recursive
	cd "$MME_DIR"
fi


cd "$MME_SRC_DIR"
if [ ! -f Makefile ]; then
	whiptail --title "MasterMe Installer" --msgbox "Could not find Makefile in cloned repo. Aborting." 10 60
	exit 1
fi

whiptail --title "MasterMe Installer" --msgbox "Building MasterMe using make..." 10 70
if make; then
	# Try to find the built binary
	BIN_PATH=""
	if [ -f "bin/master_me" ]; then
		BIN_PATH="bin/master_me"
	elif [ -f "build/master_me" ]; then
		BIN_PATH="build/master_me"
	elif [ -f "master_me" ]; then
		BIN_PATH="master_me"
	fi
	if [ -n "$BIN_PATH" ]; then
		mkdir -p "$HOME/.local/bin"
		cp "$BIN_PATH" "$MME_BIN"
		whiptail --title "MasterMe Installer" --msgbox "MasterMe built and installed to $MME_BIN.\n\nAdd $HOME/.local/bin to your PATH if needed." 10 70
	else
		whiptail --title "MasterMe Installer" --msgbox "Build succeeded but could not find the master_me binary. Please check the build output." 10 70
	fi
else
	whiptail --title "MasterMe Installer" --msgbox "Build failed. Please check the output above for errors." 10 70
	exit 1
fi

exit 0
