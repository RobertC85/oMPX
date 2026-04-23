import os
import json
from flask import Flask, request, jsonify, send_file
from glob import glob

PROFILE_DIR = os.path.join(os.path.dirname(__file__), '../modules/profiles')
BUILTIN_PROFILES = [
    'decoder-clean.env',
    'music-heavy.env',
    'talk-heavy.env',
]

app = Flask(__name__)

# Utility: parse KEY=VALUE lines

def parse_profile(text):
    result = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if '=' in line:
            k, v = line.split('=', 1)
            result[k.strip()] = v.strip().strip("'\"")
    return result

def profile_path(name):
    if name in BUILTIN_PROFILES:
        return os.path.join(PROFILE_DIR, name)
    # User-supplied: treat as absolute or relative path
    if os.path.isabs(name):
        return name
    return os.path.join(PROFILE_DIR, name)

@app.route('/api/profiles', methods=['GET'])
def list_profiles():
    files = [os.path.basename(f) for f in glob(os.path.join(PROFILE_DIR, '*.env'))]
    return jsonify({'profiles': BUILTIN_PROFILES + [f for f in files if f not in BUILTIN_PROFILES]})

@app.route('/api/profile', methods=['GET'])
def get_profile():
    name = request.args.get('name')
    path = profile_path(name)
    if not os.path.exists(path):
        return jsonify({'error': 'Profile not found'}), 404
    with open(path) as f:
        text = f.read()
    return jsonify({'name': name, 'text': text, 'params': parse_profile(text)})

@app.route('/api/profile', methods=['POST'])
def save_profile():
    data = request.json
    name = data.get('name')
    text = data.get('text')
    if not name or not text:
        return jsonify({'error': 'Missing name or text'}), 400
    path = profile_path(name)
    with open(path, 'w') as f:
        f.write(text)
    return jsonify({'ok': True})

@app.route('/api/profile/apply', methods=['POST'])
def apply_profile():
    # Save profile and attempt to apply live to Liquidsoap
    # SECURITY WARNING: Telnet is insecure; this only connects to localhost. Do NOT expose Liquidsoap telnet port externally.
    import socket
    import subprocess
    data = request.json
    name = data.get('name')
    text = data.get('text')
    if not name or not text:
        return jsonify({'error': 'Missing name or text'}), 400
    path = profile_path(name)
    with open(path, 'w') as f:
        f.write(text)

    # Try to update Liquidsoap live via telnet (localhost only)
    liq_host = "127.0.0.1"
    liq_port = 1234
    telnet_success = False
    telnet_error = None
    # Example: send a reload or custom command if your Liquidsoap script supports it
    # You may need to adjust the command below to match your Liquidsoap config
    try:
        with socket.create_connection((liq_host, liq_port), timeout=2) as s:
            # This assumes your Liquidsoap script supports a 'reload' or similar command
            s.sendall(b"reload\n")
            resp = s.recv(1024)
            telnet_success = True
    except Exception as e:
        telnet_error = str(e)

    if telnet_success:
        return jsonify({'ok': True, 'message': 'Profile applied and Liquidsoap reloaded via telnet.'})
    else:
        # Fallback: restart the service (may cause brief audio gap)
        try:
            subprocess.run(["systemctl", "restart", "ompx-liquidsoap.service"], check=True)
            return jsonify({'ok': True, 'message': f'Profile applied. Telnet reload failed ({telnet_error}); service restarted.'})
        except Exception as e:
            return jsonify({'ok': False, 'message': f'Profile saved, but failed to reload Liquidsoap: {e}'})

@app.route('/')
def index():
    # Serve the main index.html from the parent encoder directory
    html_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '../index.html'))
    return send_file(html_path, mimetype='text/html')

if __name__ == '__main__':
    # Determine port based on selected processing stack or environment
    import socket
    def port_in_use(port):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            return s.connect_ex(('127.0.0.1', port)) == 0

    # Default to 8082 unless overridden
    port = int(os.environ.get('OMPX_WEB_PORT', 8082))
    # If port is in use, try 8090, then 8181
    if port_in_use(port):
        for alt in (8090, 8181):
            if not port_in_use(alt):
                port = alt
                break
    app.run(host='0.0.0.0', port=port, debug=True)
