
######################################################################
######################################################################
# oMPX Liquidsoap Processing Script
# ---------------------------------
# This script implements the main audio processing pipeline for oMPX.
# Inspired by Stereo Tool, it provides:
#   - Pre/post gain
#   - Noise gate
#   - Multiband AGC (automatic gain control)
#   - 5-band multiband compression
#   - Limiter/clipper
#   - 3-band EQ
#   - Stereo width control
#   - Output to Icecast and HTTP preview
#
# Each program chain (Program 1 and Program 2) is processed independently.
# All parameters can be tuned for different presets or use cases.
#
# For more info, see: https://github.com/RobertC85/oMPX
######################################################################
######################################################################



# --- Logging and Telnet Control ---
set("log.file", "/home/ompx/logs/liquidsoap-processing.log")
set("server.telnet", true)
set("server.telnet.port", 1234)
set("server.telnet.bind_addr", "127.0.0.1")

agc1 = agc(agc_band1, attack=agc_attack, release=agc_release, threshold=agc_threshold, ratio=agc_ratio)
agc2 = agc(agc_band2, attack=agc_attack, release=agc_release, threshold=agc_threshold, ratio=agc_ratio)
agc3 = agc(agc_band3, attack=agc_attack, release=agc_release, threshold=agc_threshold, ratio=agc_ratio)
agc_out = add([agc1, agc2, agc3])


# --- Input Source ---
# Use ALSA loopback device as main input (customize as needed)
input = input.alsa(bufferize=false, id="main", device="hw:Loopback,1,0")

######################################################################
# --- Program 1 Processing Chain ---
# Each block below is parameterized for Program 1.
#
# 1. Preamp: Adjusts input gain
# 2. Noise Gate: Reduces noise below threshold
# 3. 3-Band AGC: Splits into low/mid/high, applies AGC to each
# 4. 3-Band EQ: Bass, mid, treble
# 5. 5-Band Multiband Compression: Crossover, compress, sum
# 6. Limiter/Clipper: Prevents digital clipping
# 7. Stereo Width: Adjusts stereo image
# 8. Post Gain: Final output gain
# 9. Output Filtering: Band-limits output
######################################################################
pre_gain_1 = 0.25           # Input gain (linear)
gate_threshold_1 = -50.0    # Gate threshold (dB)
gate_attack_1 = 0.01        # Gate attack time (s)
gate_release_1 = 0.1        # Gate release time (s)
agc_attack_1 = 0.005        # AGC attack (s)
agc_release_1 = 0.3         # AGC release (s)
agc_threshold_1 = -18.0     # AGC threshold (dB)
agc_ratio_1 = 2.0           # AGC ratio
eq_bass_1 = 1.2             # Bass EQ gain
eq_mid_1 = 1.0              # Mid EQ gain
eq_treble_1 = 1.1           # Treble EQ gain
stereo_width_1 = 1.0        # Stereo width (1.0 = normal)
post_gain_1 = 0.99          # Output gain (linear)

# Preamp and noise gate
preamp_1 = amplify(pre_gain_1, input)
gated_1 = gate(preamp_1, threshold=gate_threshold_1, attack=gate_attack_1, release=gate_release_1)

# 3-band AGC (split into low/mid/high)
agc_band1_1 = lowpass(gated_1, 300)
agc_band2_1 = bandpass(gated_1, 300, 3000)
agc_band3_1 = highpass(gated_1, 3000)
agc1_1 = agc(agc_band1_1, attack=agc_attack_1, release=agc_release_1, threshold=agc_threshold_1, ratio=agc_ratio_1)
agc2_1 = agc(agc_band2_1, attack=agc_attack_1, release=agc_release_1, threshold=agc_threshold_1, ratio=agc_ratio_1)
agc3_1 = agc(agc_band3_1, attack=agc_attack_1, release=agc_release_1, threshold=agc_threshold_1, ratio=agc_ratio_1)
agc_out_1 = add([agc1_1, agc2_1, agc3_1])

# 3-band EQ function
eq_1 = fun (s) ->
	bass = lowpass(s, 120)
	mid = bandpass(s, 120, 4000)
	treble = highpass(s, 4000)
	add([
		amplify(eq_bass_1, bass),
		amplify(eq_mid_1, mid),
		amplify(eq_treble_1, treble)
	])

# 5-band multiband compressor crossovers (Hz)
xover = [90, 280, 900, 2800]
mb_b1_1 = lowpass(agc_out_1, xover[0])
mb_b2_1 = bandpass(agc_out_1, xover[0], xover[1])
mb_b3_1 = bandpass(agc_out_1, xover[1], xover[2])
mb_b4_1 = bandpass(agc_out_1, xover[2], xover[3])

# 5-band compressor (per band)
mb_b5_1 = highpass(agc_out_1, xover[3])
mb_c1_1 = compress(mb_b1_1, threshold=-30.0, ratio=3.0, attack=0.000021, release=0.00016)
mb_c2_1 = compress(mb_b2_1, threshold=-28.0, ratio=2.8, attack=0.000021, release=0.00016)
mb_c3_1 = compress(mb_b3_1, threshold=-26.0, ratio=2.6, attack=0.000021, release=0.00016)
mb_c4_1 = compress(mb_b4_1, threshold=-24.0, ratio=2.4, attack=0.000021, release=0.00016)
mb_c5_1 = compress(mb_b5_1, threshold=-22.0, ratio=2.2, attack=0.000021, release=0.00016)
multiband_1 = add([mb_c1_1, mb_c2_1, mb_c3_1, mb_c4_1, mb_c5_1])

# Limiter/clipper and stereo width
clipper_1 = limit(multiband_1, threshold=-0.5)
stereo_1 = stereo_pan(clipper_1, width=stereo_width_1)

# Final output gain and filtering
proc_chain_1 = amplify(post_gain_1, stereo_1)
output_filtered_1 = highpass(proc_chain_1, 30.0)
output_filtered_1 = lowpass(output_filtered_1, 16900.0)

######################################################################
# --- Program 2 Processing Chain ---
# Identical to Program 1, but with independent parameters.
######################################################################
pre_gain_2 = 0.25
gate_threshold_2 = -50.0
gate_attack_2 = 0.01
gate_release_2 = 0.1
agc_attack_2 = 0.005
agc_release_2 = 0.3
agc_threshold_2 = -18.0
agc_ratio_2 = 2.0
eq_bass_2 = 1.2
eq_mid_2 = 1.0
eq_treble_2 = 1.1
stereo_width_2 = 1.0
post_gain_2 = 0.99

preamp_2 = amplify(pre_gain_2, input)
gated_2 = gate(preamp_2, threshold=gate_threshold_2, attack=gate_attack_2, release=gate_release_2)
agc_band1_2 = lowpass(gated_2, 300)
agc_band2_2 = bandpass(gated_2, 300, 3000)
agc_band3_2 = highpass(gated_2, 3000)
agc1_2 = agc(agc_band1_2, attack=agc_attack_2, release=agc_release_2, threshold=agc_threshold_2, ratio=agc_ratio_2)
agc2_2 = agc(agc_band2_2, attack=agc_attack_2, release=agc_release_2, threshold=agc_threshold_2, ratio=agc_ratio_2)
agc3_2 = agc(agc_band3_2, attack=agc_attack_2, release=agc_release_2, threshold=agc_threshold_2, ratio=agc_ratio_2)
agc_out_2 = add([agc1_2, agc2_2, agc3_2])

eq_2 = fun (s) ->
	bass = lowpass(s, 120)
	mid = bandpass(s, 120, 4000)
	treble = highpass(s, 4000)
	add([
		amplify(eq_bass_2, bass),
		amplify(eq_mid_2, mid),
		amplify(eq_treble_2, treble)
	])

mb_b1_2 = lowpass(agc_out_2, xover[0])
mb_b2_2 = bandpass(agc_out_2, xover[0], xover[1])
mb_b3_2 = bandpass(agc_out_2, xover[1], xover[2])
mb_b4_2 = bandpass(agc_out_2, xover[2], xover[3])

mb_b5_2 = highpass(agc_out_2, xover[3])
mb_c1_2 = compress(mb_b1_2, threshold=-30.0, ratio=3.0, attack=0.000021, release=0.00016)
mb_c2_2 = compress(mb_b2_2, threshold=-28.0, ratio=2.8, attack=0.000021, release=0.00016)
mb_c3_2 = compress(mb_b3_2, threshold=-26.0, ratio=2.6, attack=0.000021, release=0.00016)
mb_c4_2 = compress(mb_b4_2, threshold=-24.0, ratio=2.4, attack=0.000021, release=0.00016)
mb_c5_2 = compress(mb_b5_2, threshold=-22.0, ratio=2.2, attack=0.000021, release=0.00016)
multiband_2 = add([mb_c1_2, mb_c2_2, mb_c3_2, mb_c4_2, mb_c5_2])

clipper_2 = limit(multiband_2, threshold=-0.5)
stereo_2 = stereo_pan(clipper_2, width=stereo_width_2)

proc_chain_2 = amplify(post_gain_2, stereo_2)
output_filtered_2 = highpass(proc_chain_2, 30.0)
output_filtered_2 = lowpass(output_filtered_2, 16900.0)


######################################################################
# --- Output Section ---
#
# 1. Icecast MPX output for each program (MP3, 320kbps)
# 2. HTTP WAV preview output for browser/monitoring
######################################################################

# Icecast output for Program 1
output.icecast(%mp3(bitrate=320), host="localhost", port=8000, password="hackme", mount="/mpx1", name="MPX Program 1", description="MPX 1")
    (audio_to_stereo(output_filtered_1))

# Icecast output for Program 2
output.icecast(%mp3(bitrate=320), host="localhost", port=8000, password="hackme", mount="/mpx2", name="MPX Program 2", description="MPX 2")
    (audio_to_stereo(output_filtered_2))

# HTTP WAV preview output for Program 1
output.http(
    id="preview1",
    host="0.0.0.0",
    port=8088,
    content_type="audio/wav",
    mksafe(output_filtered_1)
)

# HTTP WAV preview output for Program 2
output.http(
    id="preview2",
    host="0.0.0.0",
    port=8089,
    content_type="audio/wav",
    mksafe(output_filtered_2)
)
