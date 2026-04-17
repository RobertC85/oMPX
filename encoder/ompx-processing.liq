# oMPX Liquidsoap processing script
# This script processes input audio, applies AGC, multiband, and gain, and outputs to stdout for ffmpeg

set("log.file", "/home/ompx/logs/liquidsoap-processing.log")
set("server.telnet", true)
set("server.telnet.port", 1234)
set("server.telnet.bind_addr", "127.0.0.1")

# Input: ALSA or file (customize as needed)
input = input.alsa(bufferize=false, id="main", device="hw:Loopback,1,0")

# AGC (simple)
agc = amplify(1.0, agc(input, attack=0.01, release=0.3, threshold=-20.0, ratio=4.0))

# Multiband compressor (simulate with multiband EQ + compress)
# For real multiband, use external LADSPA or LV2 plugins if available
band1 = lowpass(agc, 200)
band2 = bandpass(agc, 200, 2000)
band3 = highpass(agc, 2000)

comp1 = compress(band1, threshold=-30.0, ratio=3.0)
comp2 = compress(band2, threshold=-25.0, ratio=2.5)
comp3 = compress(band3, threshold=-20.0, ratio=2.0)

# Mix bands back together
multiband = add([comp1, comp2, comp3])

# Post-gain (default +6dB, can be changed via telnet)
post_gain = amplify(2.0, multiband)

# Output to stdout (for ffmpeg)
output.raw(audio_to_stereo(post_gain), id="mainout", sample_rate=192000, channels=2, format="s16le", stdout=true)
