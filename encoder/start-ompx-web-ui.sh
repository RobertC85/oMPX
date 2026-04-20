
#!/bin/bash
# oMPX Web UI Startup Script
# -------------------------
# Starts the oMPX Web UI backend (Python Flask app) and logs output.
#
# Features:
#   - Stops any running instance of the backend
#   - Starts backend in background using nohup
#   - Logs output to /var/log/ompx-web-ui.log
#
# Usage: Run as root or with sudo privileges.
#
# For more info, see: https://github.com/RobertC85/oMPX

LOGFILE="/var/log/ompx-web-ui.log"
PYTHON_SCRIPT="/opt/mpx-radio/ompx-web-ui.py"

# Stop any running instance of the backend
sudo pkill -f "$PYTHON_SCRIPT"

# Start the backend in the background with nohup
sudo nohup python3 "$PYTHON_SCRIPT" > "$LOGFILE" 2>&1 &

echo "oMPX Web UI backend started. Logs: $LOGFILE"
