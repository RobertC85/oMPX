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

# --- Generate a random password for HTTP harbor output ---
def gen_password(len) =
  base = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  pw = ""
  for i = 1 to len do
    pw := pw ^ string.extract(base, random.int(0, string.length(base)-1), 1)
  done
  pw
end

harbor_password = gen_password(16)
log("[oMPX] Liquidsoap HTTP harbor password for /preview.wav: " ^ harbor_password)

# --- Output Section ---
output.harbor(
    id="preview",
    port=8088,
    password=harbor_password,
    format=%wav,
    mount="/preview.wav",
    post_gain
)
