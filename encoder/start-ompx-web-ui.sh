#!/bin/bash
# Start oMPX Web UI backend manually and log output

LOGFILE="/var/log/ompx-web-ui.log"
PYTHON_SCRIPT="/opt/mpx-radio/ompx-web-ui.py"

# Stop any running instance
sudo pkill -f "$PYTHON_SCRIPT"

# Start the backend in the background with nohup
sudo nohup python3 "$PYTHON_SCRIPT" > "$LOGFILE" 2>&1 &

echo "oMPX Web UI backend started. Logs: $LOGFILE"
