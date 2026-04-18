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

class Handler(BaseHTTPRequestHandler):
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
                    # Commit settings to main Liquidsoap instance
                    # (Assume settings are in payload, e.g., AGC, gain, etc.)
                    # Write settings to ompx-processing.liq or send via telnet as needed
                    # For now, just restart the main service to reload settings
                    try:
                        subprocess.run(["systemctl", "restart", "ompx-liquidsoap.service"], check=True)
                        msg = "Settings applied to main output."
                    except Exception as e:
                        msg = f"Failed to apply settings: {e}"
                    self._send_json({"ok": True, "message": msg})
                    return
            def _send_json(self, obj, code=200):
                self.send_response(code)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(obj).encode())
        def do_POST(self):
            length = int(self.headers.get('Content-Length', 0))
            payload = json.loads(self.rfile.read(length)) if length else {}
            if self.path == "/api/preview_start":
                # Start preview Liquidsoap service
                try:
                    subprocess.run(["systemctl", "restart", "ompx-liquidsoap-preview.service"], check=True)
                    msg = "Preview started."
                except Exception as e:
                    msg = f"Failed to start preview: {e}"
                self._send_json({"ok": True, "message": msg})
                return
            if self.path == "/api/preview_stop":
                # Stop preview Liquidsoap service
                try:
                    subprocess.run(["systemctl", "stop", "ompx-liquidsoap-preview.service"], check=True)
                    msg = "Preview stopped."
                except Exception as e:
                    msg = f"Failed to stop preview: {e}"
                self._send_json({"ok": True, "message": msg})
                return
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
            # Apply changes to Liquidsoap via telnet
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
            # Add more parameter updates as needed
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
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def do_GET(self):
        if self.path == "/":
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            with open(os.path.join(os.path.dirname(__file__), "index.html"), "r") as f:
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
