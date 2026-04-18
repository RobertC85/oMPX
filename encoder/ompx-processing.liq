######################################################################
######################################################################
# oMPX Liquidsoap processing script (Stereo Tool-inspired defaults)
# Approximates: pre/post gain, noise gate, compressor, 5-band multiband,
# limiter, EQ, and stereo settings from provided preset
######################################################################
######################################################################


set("log.file", "/home/ompx/logs/liquidsoap-processing.log")
set("server.telnet", true)
set("server.telnet.port", 1234)
set("server.telnet.bind_addr", "127.0.0.1")

# Input: ALSA or file (customize as needed)

# Input
input = input.alsa(bufferize=false, id="main", device="hw:Loopback,1,0")


# --- Pre amplifier (Pre gain) ---
pre_gain = 0.25  # Stereo Tool: 0.25
preamp = amplify(pre_gain, input)

# --- Noise Gate ---
# Stereo Tool: Enabled=1, Noise level=1.7
# Liquidsoap's gate: threshold in dB, attack/release in seconds
gate_enabled = true
gate_threshold = -50.0  # dB, rough guess for 1.7
gate_attack = 0.01
gate_release = 0.1
gated = if gate_enabled then gate(preamp, threshold=gate_threshold, attack=gate_attack, release=gate_release) else preamp

# --- 3-band slow AGC (Singleband Compressor/AGC) ---
agc_attack = 0.005  # Stereo Tool: 0.0051
agc_release = 0.3   # Stereo Tool: 0.0051-0.3, use 0.3 for slow
agc_threshold = -18.0
agc_ratio = 2.0
agc_band1 = lowpass(gated, 300)
agc_band2 = bandpass(gated, 300, 3000)
agc_band3 = highpass(gated, 3000)
agc1 = agc(agc_band1, attack=agc_attack, release=agc_release, threshold=agc_threshold, ratio=agc_ratio)
agc2 = agc(agc_band2, attack=agc_attack, release=agc_release, threshold=agc_threshold, ratio=agc_ratio)
agc3 = agc(agc_band3, attack=agc_attack, release=agc_release, threshold=agc_threshold, ratio=agc_ratio)
agc_out = add([agc1, agc2, agc3])

# --- Equalizer (pre-multiband, 3-band, can be expanded) ---
eq_enabled = true
eq_position = "pre"  # "pre" or "post"
eq = fun (s) ->
	# Stereo Tool: Equalizer enabled=1, positions for 3 bands (approximate)
	bass = lowpass(s, 120)
	mid = bandpass(s, 120, 4000)
	treble = highpass(s, 4000)
	add([
		amplify(1.2, bass),   # +1.5dB bass
		amplify(1.0, mid),
		amplify(1.1, treble)  # +1dB treble
	])

# --- 5-band Multiband Compressor ---
# Crossover frequencies (Hz) from shell script
xover = [90, 280, 900, 2800]
mb_b1 = lowpass(agc_out, xover[0])
mb_b2 = bandpass(agc_out, xover[0], xover[1])
mb_b3 = bandpass(agc_out, xover[1], xover[2])
mb_b4 = bandpass(agc_out, xover[2], xover[3])
mb_b5 = highpass(agc_out, xover[3])
# Stereo Tool: Attack/decay speeds, ratios, thresholds approximated
mb_c1 = compress(mb_b1, threshold=-30.0, ratio=3.0, attack=0.000021, release=0.00016)
mb_c2 = compress(mb_b2, threshold=-28.0, ratio=2.8, attack=0.000021, release=0.00016)
mb_c3 = compress(mb_b3, threshold=-26.0, ratio=2.6, attack=0.000021, release=0.00016)
mb_c4 = compress(mb_b4, threshold=-24.0, ratio=2.4, attack=0.000021, release=0.00016)
mb_c5 = compress(mb_b5, threshold=-22.0, ratio=2.2, attack=0.000021, release=0.00016)
multiband = add([mb_c1, mb_c2, mb_c3, mb_c4, mb_c5])


# --- Clipper (hard limiter) ---
clipper = fun (s) ->
	# Stereo Tool: Hard limit output=1, Final limiter value=1, threshold -0.5dBFS
	limit(s, threshold=-0.5)


# --- Stereo (basic width control, not full Stereo Tool) ---
stereo_width = 1.0  # 1.0 = normal, >1 wider, <1 narrower
stereo = fun (s) -> stereo_pan(s, width=stereo_width)

# --- Post amplifier (Post gain) ---
post_gain = 0.99  # Stereo Tool: 0.99

# --- Processing chain assembly ---
proc_chain =
	if eq_enabled && eq_position == "pre" then
		amplify(post_gain, stereo(clipper(eq(multiband))))
	else if eq_enabled && eq_position == "post" then
		amplify(post_gain, stereo(eq(clipper(multiband))))
	else
		amplify(post_gain, stereo(clipper(multiband)))


# --- Output filter (final highpass/lowpass) ---
output_filtered = highpass(proc_chain, 30.0)
output_filtered = lowpass(output_filtered, 16900.0)

# --- Output ---
output.raw(audio_to_stereo(output_filtered), id="mainout", sample_rate=192000, channels=2, format="s16le", stdout=true)
