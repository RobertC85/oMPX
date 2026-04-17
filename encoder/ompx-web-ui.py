# oMPX Web UI backend (Python HTTP server)
# Extracted from oMPX-Encoder-Debian-setup.sh for maintainability
# Place your backend logic here. If you had embedded Python code in the installer, move it here.

from http.server import HTTPServer, BaseHTTPRequestHandler
from http import HTTPStatus
import json
import threading
import os
import subprocess

STATE_LOCK = threading.Lock()
STATE_FILE = "/home/ompx/.ompx_web_state.json"

def load_state():
    try:
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return {}

def save_state(state):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)

class Handler(BaseHTTPRequestHandler):
    def _send_json(self, obj, status=HTTPStatus.OK):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(obj).encode())

    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        payload = json.loads(self.rfile.read(length)) if length else {}
        if self.path == "/api/apply_mpx":
            prog = int(payload.get("program", 0))
            if prog not in (1, 2):
                self._send_json({"ok": False, "message": "Invalid program number"}, status=HTTPStatus.BAD_REQUEST)
                return
            profile = payload.get("profile") or payload.get("multiband_profile") or payload.get("MULTIBAND_PROFILE")
            post_gain = payload.get("post_gain_db") or payload.get("POST_GAIN_DB")
            if not profile:
                profile = payload.get(f"MULTIBAND_PROFILE_P{prog}") or payload.get(f"multiband_profile_p{prog}")
            if not post_gain:
                post_gain = payload.get(f"POST_GAIN_DB_P{prog}") or payload.get(f"post_gain_db_p{prog}")
            if not post_gain:
                post_gain = payload.get("post_gain_db")
            with STATE_LOCK:
                state = load_state()
                if prog == 1:
                    if profile: state["MULTIBAND_PROFILE_P1"] = profile
                    if post_gain: state["POST_GAIN_DB_P1"] = post_gain
                else:
                    if profile: state["MULTIBAND_PROFILE_P2"] = profile
                    if post_gain: state["POST_GAIN_DB_P2"] = post_gain
                save_state(state)
            profile_path = "/home/ompx/.profile"
            def replace_or_add_line(lines, key, value):
                found = False
                for i, line in enumerate(lines):
                    if line.startswith(f"{key}="):
                        lines[i] = f'{key}="{value}"
'
                        found = True
                if not found:
                    lines.append(f'{key}="{value}"
')
                return lines
            try:
                with open(profile_path, "r") as f:
                    lines = f.readlines()
            except Exception:
                lines = []
            if prog == 1:
                if profile: lines = replace_or_add_line(lines, "MULTIBAND_PROFILE_P1", profile)
                if post_gain: lines = replace_or_add_line(lines, "POST_GAIN_DB_P1", post_gain)
            else:
                if profile: lines = replace_or_add_line(lines, "MULTIBAND_PROFILE_P2", profile)
                if post_gain: lines = replace_or_add_line(lines, "POST_GAIN_DB_P2", post_gain)
            try:
                with open(profile_path, "w") as f:
                    f.writelines(lines)
            except Exception:
                pass
            try:
                subprocess.run(["systemctl", "restart", "mpx-processing-alsa.service"], check=True)
                msg = f"Applied to MPX (Program {prog}) and restarted processing."
            except Exception as e:
                msg = f"Applied to MPX (Program {prog}), but failed to restart processing: {e}"
            self._send_json({"ok": True, "message": msg})
            return
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def do_GET(self):
        if self.path == "/":
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            with open(os.path.join(os.path.dirname(__file__), "ompx-web-ui.html"), "r") as f:
                self.wfile.write(f.read().encode())
            return
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

def run():
    port = int(os.environ.get("OMPX_WEB_PORT", 8080))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"oMPX Web UI running on port {port}")
    server.serve_forever()

if __name__ == "__main__":
    run()
