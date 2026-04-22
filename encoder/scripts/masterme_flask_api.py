from flask import Flask, render_template, request, jsonify, send_from_directory
import os
import subprocess
import threading

MASTERME_BIN = os.path.expanduser("~/.local/bin/master_me")
MASTERME_CONFIG = os.path.expanduser("~/master_me_build/master_me/config.toml")
MASTERME_PROCESS = None
MASTERME_LOCK = threading.Lock()

app = Flask(__name__)

# Serve the static HTML UI
@app.route("/")
def index():
    return send_from_directory(os.path.dirname(__file__), "masterme_ui.html")

# API: Get config
@app.route("/api/config", methods=["GET"])
def get_config():
    if os.path.exists(MASTERME_CONFIG):
        with open(MASTERME_CONFIG) as f:
            return jsonify({"config": f.read()})
    return jsonify({"config": ""})

# API: Save config
@app.route("/api/config", methods=["POST"])
def save_config():
    data = request.json.get("config", "")
    with open(MASTERME_CONFIG, "w") as f:
        f.write(data)
    return jsonify({"status": "ok"})

# API: Start MasterMe
@app.route("/api/start", methods=["POST"])
def start_masterme():
    global MASTERME_PROCESS
    with MASTERME_LOCK:
        if MASTERME_PROCESS is None or MASTERME_PROCESS.poll() is not None:
            MASTERME_PROCESS = subprocess.Popen([MASTERME_BIN, "-c", MASTERME_CONFIG])
            return jsonify({"status": "started"})
        else:
            return jsonify({"status": "already running"})

# API: Stop MasterMe
@app.route("/api/stop", methods=["POST"])
def stop_masterme():
    global MASTERME_PROCESS
    with MASTERME_LOCK:
        if MASTERME_PROCESS and MASTERME_PROCESS.poll() is None:
            MASTERME_PROCESS.terminate()
            MASTERME_PROCESS.wait(timeout=5)
            MASTERME_PROCESS = None
            return jsonify({"status": "stopped"})
        else:
            return jsonify({"status": "not running"})

# API: Status
@app.route("/api/status", methods=["GET"])
def status():
    running = False
    with MASTERME_LOCK:
        running = MASTERME_PROCESS is not None and MASTERME_PROCESS.poll() is None
    return jsonify({"running": running})

if __name__ == "__main__":
    port = int(os.environ.get("MASTERME_WEB_PORT", 8082))
    app.run(host="0.0.0.0", port=port, debug=False)
