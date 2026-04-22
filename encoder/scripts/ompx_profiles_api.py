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
    # For now, just save and acknowledge; real-time apply logic can be added here
    data = request.json
    name = data.get('name')
    text = data.get('text')
    if not name or not text:
        return jsonify({'error': 'Missing name or text'}), 400
    path = profile_path(name)
    with open(path, 'w') as f:
        f.write(text)
    # TODO: trigger live reload if supported
    return jsonify({'ok': True})

@app.route('/')
def index():
    html_path = os.path.join(os.path.dirname(__file__), 'ompx_profiles_ui.html')
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
