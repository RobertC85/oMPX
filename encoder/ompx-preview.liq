######################################################################
# oMPX Liquidsoap Preview Script (MINIMAL COMPATIBILITY VERSION)
######################################################################

# --- Logging and Telnet Control ---
set("log.file", "/home/ompx/logs/liquidsoap-preview.log")
set("server.telnet", true)
set("server.telnet.port", 1235)
set("server.telnet.bind_addr", "127.0.0.1")

# --- Input Source (test: sine wave) ---
input = sine()

# --- Post-Gain Only ---
post_gain = amplify(2.0, input)

# --- Output Section ---
# HTTP WAV preview for web UI
output.harbor(
	id="preview",
	port=8088,
	password="hackme", # change this if exposed
	format="wav",
	mount="/preview.wav",
	post_gain
)
