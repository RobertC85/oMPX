# oMPX Liquidsoap preview script
# Processes input audio with test settings and outputs to both Icecast /preview and browser-accessible HTTP stream

set("log.file", "/home/ompx/logs/liquidsoap-preview.log")
set("server.telnet", true)
set("server.telnet.port", 1235)
set("server.telnet.bind_addr", "127.0.0.1")

# Input: ALSA or file (customize as needed)
input = input.alsa(bufferize=false, id="preview", device="hw:Loopback,1,0")

# AGC (simple)
agc = amplify(1.0, agc(input, attack=0.01, release=0.3, threshold=-20.0, ratio=4.0))

# Multiband compressor (simulate with multiband EQ + compress)
band1 = lowpass(agc, 200)
band2 = bandpass(agc, 200, 2000)
band3 = highpass(agc, 2000)

comp1 = compress(band1, threshold=-30.0, ratio=3.0)
comp2 = compress(band2, threshold=-25.0, ratio=2.5)
comp3 = compress(band3, threshold=-20.0, ratio=2.0)

multiband = add([comp1, comp2, comp3])

# Post-gain (default +6dB, can be changed via telnet)
post_gain = amplify(2.0, multiband)

# Output to Icecast /preview
output.icecast(%mp3, host="127.0.0.1", port=8000, password="hackme", mount="/preview", name="oMPX Preview", source=post_gain)

# Output to browser-accessible HTTP stream (wav)
output.http(server.port=8088, content_type="audio/wav", id="previewhttp", post_gain)
