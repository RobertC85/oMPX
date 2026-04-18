# oMPX Web UI backend (Python HTTP server)
# Extracted from oMPX-Encoder-Debian-setup.sh for maintainability
# Place your backend logic here. If you had embedded Python code in the installer, move it here.

from http.server import HTTPServer, BaseHTTPRequestHandler
from http import HTTPStatus
import json
import threading
import os
import subprocess
import requests
from rds_utils import recreate_rds_json

STATE_LOCK = threading.Lock()
STATE_FILE = "/home/ompx/.ompx_web_state.json"
STATE_FILE_BACKUP = "/home/ompx/.ompx_web_state.prev.json"

def load_state():
    try:
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return {}

def save_state(state):
    # Backup current state before saving new one
    import shutil
    try:
        shutil.copy2(STATE_FILE, STATE_FILE_BACKUP)
    except Exception:
        pass
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)

'
')

class Handler(BaseHTTPRequestHandler):
        def _is_local_kiosk(self):
            # Check if kiosk mode is enabled and request is from localhost
            kiosk = os.environ.get("OMPX_WEB_KIOSK_ENABLE", "false").lower() == "true"
            # Accept both IPv4 and IPv6 loopback
            client = self.client_address[0]
            is_local = client in ("127.0.0.1", "::1", "localhost")
            return kiosk and is_local

    def _send_json(self, obj, status=HTTPStatus.OK):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(obj).encode())

    def do_POST(self):
        # If UI auth is enabled but this is local kiosk, skip auth
        if os.environ.get("OMPX_WEB_AUTH_ENABLE", "false").lower() == "true" and not self._is_local_kiosk():
            # Simple password check (could be improved)
            auth = self.headers.get("Authorization")
            expected = os.environ.get("OMPX_WEB_AUTH_PASSWORD", "")
            if not auth or auth != f"Bearer {expected}":
                self._send_json({"ok": False, "message": "Authentication required"}, status=HTTPStatus.UNAUTHORIZED)
                return
        length = int(self.headers.get('Content-Length', 0))
        payload = json.loads(self.rfile.read(length)) if length else {}
        if self.path == "/api/undo":
            # Restore previous state from backup
            import shutil
            try:
                shutil.copy2(STATE_FILE_BACKUP, STATE_FILE)
                msg = "Settings reverted to previous state."
            except Exception as e:
                msg = f"Failed to revert: {e}"
            self._send_json({"ok": True, "message": msg})
            return
        if self.path == "/api/apply_mpx":
            prog = int(payload.get("program", 0))
            if prog not in (1, 2):
                self._send_json({"ok": False, "message": "Invalid program number"}, status=HTTPStatus.BAD_REQUEST)
                return
            # Accept all UI-exposed options, fallback to installer env or previous state
            def get_opt(key, env_key=None, default=None):
                return (
                    payload.get(key)
                    or payload.get(key.lower())
                    or payload.get(key.upper())
                    or (os.environ.get(env_key or key.upper()) if (env_key or key.upper()) in os.environ else None)
                    or default
                )
            profile = get_opt("multiband_profile", "MULTIBAND_PROFILE")
            post_gain = get_opt("post_gain_db", "POST_GAIN_DB")
            pre_gain = get_opt("pre_gain_db", "PRE_GAIN_DB")
            stereo_width = get_opt("stereo_width", "STEREO_WIDTH")
            agc_filter = get_opt("agc_filter", "AGC_FILTER")
            output_limit = get_opt("output_limit", "OUTPUT_LIMIT")
            hpf_freq = get_opt("hpf_freq", "HPF_FREQ")
            lpf_freq = get_opt("lpf_freq", "LPF_FREQ")
            # Save to state
            with STATE_LOCK:
                state = load_state()
                prefix = f"P{prog}" if prog in (1,2) else ""
                if profile: state[f"MULTIBAND_PROFILE_{prefix}"] = profile
                if post_gain: state[f"POST_GAIN_DB_{prefix}"] = post_gain
                if pre_gain: state[f"PRE_GAIN_DB_{prefix}"] = pre_gain
                if stereo_width: state[f"STEREO_WIDTH_{prefix}"] = stereo_width
                if agc_filter: state[f"AGC_FILTER_{prefix}"] = agc_filter
                if output_limit: state[f"OUTPUT_LIMIT_{prefix}"] = output_limit
                if hpf_freq: state[f"HPF_FREQ_{prefix}"] = hpf_freq
                if lpf_freq: state[f"LPF_FREQ_{prefix}"] = lpf_freq
                save_state(state)
            # Write to .profile for persistence
            profile_path = "/home/ompx/.profile"
            def replace_or_add_line(lines, key, value):
                found = False
                for i, line in enumerate(lines):
                    if line.startswith(f"{key}="):
                        lines[i] = f'{key}="{value}"\n'
                        found = True
                if not found:
                    lines.append(f'{key}="{value}"\n')
                return lines
            try:
                with open(profile_path, "r") as f:
                    lines = f.readlines()
            except Exception:
                lines = []
            def persist(key, value):
                nonlocal lines
                if value: lines = replace_or_add_line(lines, key, value)
            persist(f"MULTIBAND_PROFILE_P{prog}", profile)
            persist(f"POST_GAIN_DB_P{prog}", post_gain)
            persist(f"PRE_GAIN_DB_P{prog}", pre_gain)
            persist(f"STEREO_WIDTH_P{prog}", stereo_width)
            persist(f"AGC_FILTER_P{prog}", agc_filter)
            persist(f"OUTPUT_LIMIT_P{prog}", output_limit)
            persist(f"HPF_FREQ_P{prog}", hpf_freq)
            persist(f"LPF_FREQ_P{prog}", lpf_freq)
            try:
                with open(profile_path, "w") as f:
                    f.writelines(lines)
            except Exception:
                pass
            # Apply changes to Liquidsoap via telnet (if possible)
            import socket
            liq_host = "127.0.0.1"
            liq_port = 1234
            cmds = []
            if post_gain:
                try:
                    gain_val = float(post_gain)
                    cmds.append(f"var post_gain = amplify({2**(gain_val/6):.3f}, multiband)\n")
                except Exception:
                    pass
            # Add more parameter updates as needed (stereo_width, agc_filter, etc.)
            response = ""
            try:
                with socket.create_connection((liq_host, liq_port), timeout=2) as s:
                    for cmd in cmds:
                        s.sendall(cmd.encode())
                        response += s.recv(1024).decode()
                msg = f"Applied to MPX (Program {prog}) and updated Liquidsoap."
            except Exception as e:
                msg = f"Applied to MPX (Program {prog}), but failed to update Liquidsoap: {e}"
            self._send_json({"ok": True, "message": msg})
            return
        if self.path == "/api/preview_start":
            # Accept preview options and start preview service
            preview_format = payload.get("preview_format", "mp3")
            # Optionally apply preview settings (profile, gain, etc.)
            # For now, just restart preview service
            try:
                subprocess.run(["systemctl", "restart", "ompx-liquidsoap-preview.service"], check=True)
                msg = "Preview started."
            except Exception as e:
                msg = f"Failed to start preview: {e}"
            self._send_json({"ok": True, "message": msg, "preview_format": preview_format})
            return
        if self.path == "/api/preview_stop":
            try:
                subprocess.run(["systemctl", "stop", "ompx-liquidsoap-preview.service"], check=True)
                msg = "Preview stopped."
            except Exception as e:
                msg = f"Failed to stop preview: {e}"
            self._send_json({"ok": True, "message": msg})
            return
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")


    def do_GET(self):
        if self.path == "/":
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            with open(os.path.join(os.path.dirname(__file__), "index.html"), "r") as f:
                self.wfile.write(f.read().encode())
            return
        # Audio preview endpoints
        if self.path.startswith("/api/preview.mp3"):
            # Proxy from Icecast (MP3)
            try:
                resp = requests.get("http://127.0.0.1:8082/preview", stream=True, timeout=5)
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "audio/mpeg")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                for chunk in resp.iter_content(chunk_size=4096):
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                return
            except Exception as e:
                self.send_error(HTTPStatus.SERVICE_UNAVAILABLE, f"MP3 preview unavailable: {e}")
                return
        if self.path.startswith("/api/preview.wav"):
            # Proxy from Liquidsoap HTTP output (WAV)
            try:
                resp = requests.get("http://127.0.0.1:8088/", stream=True, timeout=5)
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "audio/wav")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                for chunk in resp.iter_content(chunk_size=4096):
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                return
            except Exception as e:
                self.send_error(HTTPStatus.SERVICE_UNAVAILABLE, f"WAV preview unavailable: {e}")
                return
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

def run():
    # Recreate RDS JSON files on every launch
    recreate_rds_json()
    # Default port is 8082, but can be overridden by OMPX_WEB_PORT environment variable.
    # In the future, allow user to set this via the UI advanced tab.
    port = int(os.environ.get("OMPX_WEB_PORT", 8082))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"oMPX Web UI running on port {port}")
    server.serve_forever()

if __name__ == "__main__":
    run()
