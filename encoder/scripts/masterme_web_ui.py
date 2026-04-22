from flask import Flask, render_template_string, request, redirect, url_for, flash
import os
import subprocess
import threading
import signal

MASTERME_BIN = os.path.expanduser("~/.local/bin/master_me")
MASTERME_CONFIG = os.path.expanduser("~/master_me_build/master_me-1.3.1/config.toml")
MASTERME_PROCESS = None
MASTERME_LOCK = threading.Lock()

app = Flask(__name__)
app.secret_key = "masterme_secret"

TEMPLATE = '''
<!doctype html>
<title>MasterMe Web UI</title>
<h2>MasterMe Web Interface</h2>
<p>Status: <b>{{ status }}</b></p>
<form method="post" action="/start">
    <button type="submit" {% if running %}disabled{% endif %}>Start MasterMe</button>
</form>
<form method="post" action="/stop">
    <button type="submit" {% if not running %}disabled{% endif %}>Stop MasterMe</button>
</form>
<form method="post" action="/edit">
    <textarea name="config" rows="15" cols="80">{{ config }}</textarea><br>
    <button type="submit">Save Config</button>
</form>
{% with messages = get_flashed_messages() %}
  {% if messages %}
    <ul>
    {% for message in messages %}
      <li>{{ message }}</li>
    {% endfor %}
    </ul>
  {% endif %}
{% endwith %}
'''

def is_running():
    with MASTERME_LOCK:
        return MASTERME_PROCESS is not None and MASTERME_PROCESS.poll() is None

def start_masterme():
    global MASTERME_PROCESS
    with MASTERME_LOCK:
        if not is_running():
            MASTERME_PROCESS = subprocess.Popen([MASTERME_BIN, "-c", MASTERME_CONFIG])

def stop_masterme():
    global MASTERME_PROCESS
    with MASTERME_LOCK:
        if is_running():
            MASTERME_PROCESS.terminate()
            try:
                MASTERME_PROCESS.wait(timeout=5)
            except subprocess.TimeoutExpired:
                MASTERME_PROCESS.kill()
            MASTERME_PROCESS = None

def read_config():
    if os.path.exists(MASTERME_CONFIG):
        with open(MASTERME_CONFIG) as f:
            return f.read()
    return ""

def write_config(data):
    with open(MASTERME_CONFIG, "w") as f:
        f.write(data)

@app.route("/", methods=["GET"])
def index():
    return render_template_string(TEMPLATE, status="Running" if is_running() else "Stopped", running=is_running(), config=read_config())

@app.route("/start", methods=["POST"])
def start():
    start_masterme()
    flash("MasterMe started.")
    return redirect(url_for("index"))

@app.route("/stop", methods=["POST"])
def stop():
    stop_masterme()
    flash("MasterMe stopped.")
    return redirect(url_for("index"))

@app.route("/edit", methods=["POST"])
def edit():
    write_config(request.form["config"])
    flash("Config updated.")
    return redirect(url_for("index"))

if __name__ == "__main__":
    port = int(os.environ.get("MASTERME_WEB_PORT", 8082))
    app.run(host="0.0.0.0", port=port, debug=False)
