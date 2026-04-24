
# oMPX Web UI backend (Python HTTP server)
import os
# -------------------------------------------------------------
# This script implements the backend HTTP API and static file server
# for the oMPX web UI. It is designed to be run as a service,
# typically behind an Nginx reverse proxy. All backend logic for
# state management, profile application, and preview control is here.
#
# Key features:
# - Handles all POST/GET API requests from the web UI
# - Manages persistent state for audio processing profiles
# - Proxies audio preview streams from Icecast/Liquidsoap
# - Controls preview services and applies settings to Liquidsoap
# - Designed for maintainability and open source clarity
# -------------------------------------------------------------

import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from http import HTTPStatus
import json
import threading
import subprocess
import requests
import socket
import time
from rds_utils import recreate_rds_json


# Thread lock for safe concurrent state access (multiple requests may access state)
STATE_LOCK = threading.Lock()
# Main state file for persistent UI/backend settings
STATE_FILE = "/home/ompx/.ompx_web_state.json"
# Backup state file for undo/revert support
STATE_FILE_BACKUP = "/home/ompx/.ompx_web_state.prev.json"


# Load the persistent state from disk (returns dict, or empty if missing/corrupt)
def load_state():
    try:
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    except Exception:
        # If file missing or corrupt, return empty state
        return {}


# Save the persistent state to disk, with backup for undo
def save_state(state):
    import shutil
    try:
        shutil.copy2(STATE_FILE, STATE_FILE_BACKUP)
    except Exception:
        # Ignore if backup fails (e.g., first run)
        pass
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)





# Main HTTP handler for oMPX Web UI backend
# Handles all HTTP requests (GET/POST) for the API and static frontend
class Handler(BaseHTTPRequestHandler):

    # Real-time parameter update endpoint
    def _handle_update_param(self, payload):
        prog = int(payload.get("program", 0))
        param = payload.get("param")
        value = payload.get("value")
        if prog not in (1, 2) or not param:
            self._send_json({"ok": False, "message": "Invalid program or parameter"}, status=HTTPStatus.BAD_REQUEST)
            return
        # Update state
        with STATE_LOCK:
            state = load_state()
            prefix = f"P{prog}"
            state_key = f"{param}_{prefix}"
            state[state_key] = value
            save_state(state)
        # Optionally, update .profile and/or Liquidsoap here if needed
        self._send_json({"ok": True, "message": f"{param} updated for Program {prog}"})
        return


    def _is_local_kiosk(self):
        """
        Returns True if kiosk mode is enabled and the request is from localhost.
        Used to bypass authentication for trusted local kiosk setups.
        """
        kiosk = os.environ.get("OMPX_WEB_KIOSK_ENABLE", "false").lower() == "true"
        client = self.client_address[0]
        is_local = client in ("127.0.0.1", "::1", "localhost")
        return kiosk and is_local


    # Utility: send a JSON response with given status
    def _send_json(self, obj, status=HTTPStatus.OK):
        """
        Utility: Send a JSON response with the given status code.
        """
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(obj).encode())


    def do_POST(self):
        """
        Handle POST requests for all API endpoints.
        Implements authentication, state management, and control actions.
        """
        # Parse JSON payload (if any)
        length = int(self.headers.get('Content-Length', 0))
        payload = json.loads(self.rfile.read(length)) if length else {}

        # Real-time param update
        if self.path == "/api/update_param":
            return self._handle_update_param(payload)
        # Authentication is disabled by default for MVP. To enable, set OMPX_WEB_AUTH_ENABLE=true in the environment.
        # Future: Enforce HTTPS and authentication for production deployments.
        if os.environ.get("OMPX_WEB_AUTH_ENABLE", "false").lower() == "true" and not self._is_local_kiosk():
            # Simple password check (Bearer token)
            auth = self.headers.get("Authorization")
            expected = os.environ.get("OMPX_WEB_AUTH_PASSWORD", "")
            if not auth or auth != f"Bearer {expected}":
                self._send_json({"ok": False, "message": "Authentication required"}, status=HTTPStatus.UNAUTHORIZED)
                return
        # Parse JSON payload (if any)
        length = int(self.headers.get('Content-Length', 0))
        payload = json.loads(self.rfile.read(length)) if length else {}

        # Undo: revert to previous state
        if self.path == "/api/undo":
            import shutil
            try:
                shutil.copy2(STATE_FILE_BACKUP, STATE_FILE)
                msg = "Settings reverted to previous state."
            except Exception as e:
                msg = f"Failed to revert: {e}"
            self._send_json({"ok": True, "message": msg})
            return

        # Apply MPX settings: update state, persist to .profile, and optionally update Liquidsoap
        if self.path == "/api/apply_mpx":
            prog = int(payload.get("program", 0))
            if prog not in (1, 2):
                self._send_json({"ok": False, "message": "Invalid program number"}, status=HTTPStatus.BAD_REQUEST)
                return
            # Helper to get option from payload, env, or default
            def get_opt(key, env_key=None, default=None):
                return (
                    payload.get(key)
                    or payload.get(key.lower())
                    or payload.get(key.upper())
                    or (os.environ.get(env_key or key.upper()) if (env_key or key.upper()) in os.environ else None)
                    or default
                )
            # Extract all relevant settings
            profile = get_opt("multiband_profile", "MULTIBAND_PROFILE")
            post_gain = get_opt("post_gain_db", "POST_GAIN_DB")
            pre_gain = get_opt("pre_gain_db", "PRE_GAIN_DB")
            stereo_width = get_opt("stereo_width", "STEREO_WIDTH")
            agc_filter = get_opt("agc_filter", "AGC_FILTER")
            output_limit = get_opt("output_limit", "OUTPUT_LIMIT")
            hpf_freq = get_opt("hpf_freq", "HPF_FREQ")
            lpf_freq = get_opt("lpf_freq", "LPF_FREQ")
            # Save to state (thread-safe)
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
            # Persist to .profile for system-wide use
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
            # Optionally update Liquidsoap via telnet (if running)
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

        # Preview start: restart preview service (Liquidsoap)
        if self.path == "/api/preview_start":
            preview_format = payload.get("preview_format", "mp3")
            # Optionally, could apply preview settings here
            try:
                subprocess.run(["systemctl", "restart", "ompx-liquidsoap-preview.service"], check=True)
                msg = "Preview started."
            except Exception as e:
                msg = f"Failed to start preview: {e}"
            self._send_json({"ok": True, "message": msg, "preview_format": preview_format})
            return

        # Preview stop: stop preview service
        if self.path == "/api/preview_stop":
            try:
                subprocess.run(["systemctl", "stop", "ompx-liquidsoap-preview.service"], check=True)
                msg = "Preview stopped."
            except Exception as e:
                msg = f"Failed to stop preview: {e}"
            self._send_json({"ok": True, "message": msg})
            return

        # Unknown POST endpoint: always return JSON for /api/*
        if self.path.startswith("/api/"):
            self._send_json({"ok": False, "message": f"Unknown API endpoint: {self.path}"}, status=HTTPStatus.NOT_FOUND)
        else:
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")




    def do_GET(self):
        """
        Handle GET requests for the root (serves index.html), static files, and audio preview endpoints.
        """
        import re
        import mimetypes
        # Serve the main frontend (index.html) at root or with cache-busting query
        if self.path == "/" or re.match(r"^/\?v=", self.path):
            self._serve_static_file("index.html")
            return

        # Serve any static file in the encoder directory (html, js, css, images, etc.)
        static_file_match = re.match(r"^/([\w\-\.]+)(\?.*)?$", self.path)
        if static_file_match:
            filename = static_file_match.group(1)
            import os
            file_path = os.path.join(os.path.dirname(__file__), filename)
            if os.path.isfile(file_path):
                self._serve_static_file(filename)
                return

        # Audio preview endpoint: MP3 (proxied from Icecast /preview mount)
        if self.path.startswith("/api/preview.mp3"):
            mount = "/preview"
            try:
                resp = requests.get(f"http://127.0.0.1:8000{mount}", stream=True, timeout=5)
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "audio/mpeg")
                self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
                self.send_header("Pragma", "no-cache")
                self.send_header("Expires", "0")
                self.end_headers()
                for chunk in resp.iter_content(chunk_size=4096):
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                return
            except Exception as e:
                self.send_error(HTTPStatus.SERVICE_UNAVAILABLE, f"MP3 preview unavailable: {e}")
                return

        # Audio preview endpoint: WAV (proxied from Liquidsoap HTTP output)
        if self.path.startswith("/api/preview.wav"):
            # Check if port 8088 is open (Liquidsoap HTTP output)
            def is_port_open(host, port):
                try:
                    with socket.create_connection((host, port), timeout=1):
                        return True
                except Exception:
                    return False

            if not is_port_open("127.0.0.1", 8088):
                # Try to start Liquidsoap preview in background
                liq_path = os.path.join(os.path.dirname(__file__), "ompx-preview.liq")
                liq_bin = "/usr/bin/liquidsoap"
                try:
                    subprocess.Popen([liq_bin, liq_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    # Wait briefly for it to start
                    for _ in range(10):
                        if is_port_open("127.0.0.1", 8088):
                            break
                        time.sleep(0.5)
                except Exception as e:
                    self.send_error(HTTPStatus.SERVICE_UNAVAILABLE, f"Failed to auto-start Liquidsoap: {e}")
                    return

            # Now try to proxy the WAV stream
            try:
                resp = requests.get("http://127.0.0.1:8088/", stream=True, timeout=5)
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "audio/wav")
                self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
                self.send_header("Pragma", "no-cache")
                self.send_header("Expires", "0")
                self.end_headers()
                for chunk in resp.iter_content(chunk_size=4096):
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                return
            except Exception as e:
                self.send_error(HTTPStatus.SERVICE_UNAVAILABLE, f"WAV preview unavailable: {e}")
                return

        # Unknown GET endpoint: always return JSON for /api/*
        if self.path.startswith("/api/"):
            self._send_json({"ok": False, "message": f"Unknown API endpoint: {self.path}"}, status=HTTPStatus.NOT_FOUND)
        else:
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def _serve_static_file(self, filename):
        import mimetypes, os
        file_path = os.path.join(os.path.dirname(__file__), filename)
        if not os.path.isfile(file_path):
            self.send_error(HTTPStatus.NOT_FOUND, "File not found")
            return
        # Guess the content type
        content_type, _ = mimetypes.guess_type(file_path)
        if not content_type:
            content_type = "application/octet-stream"
        try:
            with open(file_path, "rb") as f:
                data = f.read()
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            self.send_error(HTTPStatus.INTERNAL_SERVER_ERROR, f"Failed to serve file: {e}")
            return
        mime, _ = mimetypes.guess_type(filename)
        # Always set correct MIME type for .js and .css
        if filename.endswith('.js'):
            mime = 'application/javascript'
        elif filename.endswith('.css'):
            mime = 'text/css'
        elif filename.endswith('.html'):
            mime = 'text/html'
        elif not mime:
            mime = 'application/octet-stream'
        # Debug log for Content-Type
        print(f"[oMPX] Serving {filename} with Content-Type: {mime}")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime)
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.end_headers()
        with open(file_path, "rb") as f:
            self.wfile.write(f.read())


# Entrypoint: start the backend server
def run():
    # Always recreate RDS JSON files on launch (ensures defaults exist)
    recreate_rds_json()
    # Bind to 127.0.0.1:5000 by default for Nginx proxying (can override with OMPX_WEB_PORT)
    # In the future, allow user to set this via the UI advanced tab.
    port = int(os.environ.get("OMPX_WEB_PORT", 5000))
    server = HTTPServer(("127.0.0.1", port), Handler)
    print(f"oMPX Web UI running on 127.0.0.1:{port} (for Nginx proxy)")
    server.serve_forever()


# Standard Python entrypoint
if __name__ == "__main__":
    run()
