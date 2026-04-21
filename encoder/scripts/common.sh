#!/usr/bin/env bash
# Common utility functions and shared variables for oMPX scripts
set -euo pipefail

OMPX_USER="ompx"
OMPX_HOME="/home/ompx"
OMPX_LOG_DIR="${OMPX_HOME}/logs"
OMPX_SHELL="/bin/bash"
SYS_SCRIPTS_DIR="/opt/mpx-radio"
FIFOS_DIR="${SYS_SCRIPTS_DIR}/fifos"
SYSTEMD_DIR="/etc/systemd/system"
STEREO_TOOL_WRAPPER="/usr/local/bin/stereo-tool"
STEREO_TOOL_ENTERPRISE_BIN="${OMPX_HOME}/stereo-tool-enterprise/stereo-tool-enterprise"
STEREO_TOOL_ENTERPRISE_LAUNCHER="/usr/local/bin/stereo-tool-enterprise-launch"
STEREO_TOOL_ENTERPRISE_SERVICE="${SYSTEMD_DIR}/stereo-tool-enterprise.service"
OMPX_STREAM_PULL_SERVICE="${SYSTEMD_DIR}/mpx-stream-pull.service"
OMPX_SOURCE1_SERVICE="${SYSTEMD_DIR}/mpx-source1.service"
OMPX_SOURCE2_SERVICE="${SYSTEMD_DIR}/mpx-source2.service"
RDS_SYNC_PROG1_SERVICE="${SYSTEMD_DIR}/rds-sync-prog1.service"
RDS_SYNC_PROG2_SERVICE="${SYSTEMD_DIR}/rds-sync-prog2.service"
OMPX_WEB_UI_SERVICE="${SYSTEMD_DIR}/ompx-web-ui.service"
OMPX_WEB_KIOSK_SERVICE="${SYSTEMD_DIR}/ompx-web-kiosk.service"
OMPX_ADD="/usr/local/bin/ompx_add_source"
ASOUND_CONF_PATH="/etc/asound.conf"
OMPX_AUDIO_UDEV_RULE="/etc/udev/rules.d/70-ompx-audio.rules"
ASOUND_MAP_HELPER="/usr/local/bin/asound-map"
ASOUND_SWITCH_HELPER="/usr/local/bin/asound-switch"
SAMPLE_RATE=192000
NON_MPX_SAMPLE_RATE="${NON_MPX_SAMPLE_RATE:-48000}"
CRON_SLEEP=10

# Service management abstraction for systemd/Devuan/other
has_systemd() {
	command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

service_action() {
	# Usage: service_action <action> <service_name>
	local action="$1"
	local svc="$2"
	if has_systemd; then
		if [ "$action" = "daemon-reload" ]; then
			systemctl daemon-reload || true
		else
			systemctl "$action" "$svc" 2>/dev/null || true
		fi
	elif command -v service >/dev/null 2>&1; then
		local svc_base="${svc%.service}"
		case "$action" in
			start|stop|restart)
				service "$svc_base" "$action" 2>/dev/null || true
				;;
			enable|disable|daemon-reload)
				echo "[INFO] Skipping '$action' for $svc_base (no systemd)"
				;;
			*)
				echo "[WARNING] Unknown service action: $action"
				;;
		esac
	else
		echo "[WARNING] No supported service manager (systemd or service) found; skipping $action for $svc"
	fi
}
