
######################################################################
# oMPX Liquidsoap Preview Script
# -----------------------------
# This script provides a simplified audio processing chain for preview/testing.
#
# Features:
#   - Simple AGC (automatic gain control)
#   - 3-band simulated multiband compression
#   - Post-gain for loudness
#   - Outputs to both Icecast (MP3) and HTTP (WAV) for browser preview
#
# Used for: Patch preview, test streams, and browser-accessible monitoring.
#
# For more info, see: https://github.com/RobertC85/oMPX
######################################################################

# --- Logging and Telnet Control ---
set("log.file", "/home/ompx/logs/liquidsoap-preview.log")
set("server.telnet", true)
set("server.telnet.port", 1235)
set("server.telnet.bind_addr", "127.0.0.1")

# --- Input Source ---
# Use ALSA loopback device as preview input (customize as needed)
input = input.alsa(bufferize=false, id="preview", device="hw:Loopback,1,0")

# --- Simple AGC ---
# Fast attack/release, moderate threshold/ratio
agc = amplify(1.0, agc(input, attack=0.01, release=0.3, threshold=-20.0, ratio=4.0))

# --- Simulated Multiband Compression ---
# Split into 3 bands, compress each, then sum
band1 = lowpass(agc, 200)
band2 = bandpass(agc, 200, 2000)
band3 = highpass(agc, 2000)

comp1 = compress(band1, threshold=-30.0, ratio=3.0)
comp2 = compress(band2, threshold=-25.0, ratio=2.5)
comp3 = compress(band3, threshold=-20.0, ratio=2.0)

multiband = add([comp1, comp2, comp3])

# --- Post-Gain ---
# Default +6dB (amplify 2.0), can be changed via telnet
post_gain = amplify(2.0, multiband)

# --- Output Section ---
#
# 1. Icecast MP3 output for preview listening
# 2. HTTP WAV output for browser/monitoring

# Output to Icecast /preview (MP3)
output.icecast(%mp3, host="127.0.0.1", port=8000, password="hackme", mount="/preview", name="oMPX Preview", source=post_gain)

# Output to browser-accessible HTTP stream (WAV)
output.http(server.port=8088, content_type="audio/wav", id="previewhttp", post_gain)
