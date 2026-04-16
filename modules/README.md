# modules

Reusable processing modules for oMPX.

## multiband_agc.sh

A standalone FFmpeg processing module that provides:
- 5-band compression (default profile: waxdreams2-5band)
- wideband AGC (via dynaudnorm)
- output limiter protection
- output filter shaping (high-pass and low-pass)
- dry/wet parallel blend
- stereo width control
- per-band trim controls

Profiles:
- waxdreams2-5band (default): fast and dense, inspired by your Stereo Tool preset direction
- waxdreams2-safe: softer long-listen variant of the above
- fm-loud: extra punch and density for loud FM-style chains
- voice-safe: speech-forward with gentler high end
- classic-3band: smoother legacy profile
- decoder-clean: external profile tuned for clean transport to decoder-side processing
- talk-heavy: external profile tuned for spoken-word clarity
- music-heavy: external profile tuned for denser music programs

External profile files are stored in [modules/profiles/](modules/profiles/) and loaded with `--profile <name>`.

Default behavior:
- input: ALSA device `default`
- output: ALSA device `default`
- sample rate: 48000

Quick example:
```bash
cd /workspaces/oMPX/modules
chmod +x ./multiband_agc.sh
./multiband_agc.sh --input-url ompx_prg1in_cap --output-url ompx_prg1in --sample-rate 192000
```

Profile examples:
```bash
# Default Stereo Tool-inspired 5-band profile
./multiband_agc.sh --profile waxdreams2-5band --input-url ompx_prg1in_cap --output-url ompx_prg1in

# Safer long-listen version
./multiband_agc.sh --profile waxdreams2-safe --input-url ompx_prg1in_cap --output-url ompx_prg1in

# Older softer profile
./multiband_agc.sh --profile classic-3band --input-url ompx_prg1in_cap --output-url ompx_prg1in

# Show all built-in profiles
./multiband_agc.sh --list-profiles

# Show resolved config for a profile without running ffmpeg
./multiband_agc.sh --profile music-heavy --show-config

# Print the generated ffmpeg command only
./multiband_agc.sh --profile music-heavy --dry-run

# Load external file-based profiles
./multiband_agc.sh --profile decoder-clean --input-url ompx_prg1in_cap --output-url ompx_prg1in
./multiband_agc.sh --profile talk-heavy --input-url ompx_prg1in_cap --output-url ompx_prg1in
./multiband_agc.sh --profile music-heavy --input-url ompx_prg1in_cap --output-url ompx_prg1in
```

Advanced tuning example:
```bash
./multiband_agc.sh \
	--profile fm-loud \
	--input-url ompx_prg1in_cap \
	--output-url ompx_prg1in \
	--sample-rate 192000 \
	--parallel-dry 0.10 \
	--stereo-width 1.15 \
	--band1-trim-db 1.0 \
	--band5-trim-db -0.8 \
	--hpf 30 \
	--lpf 15000 \
	--hf-tame-db -1.5 \
	--hf-tame-freq 7000
```

Environment override example:
```bash
INPUT_URL=hw:Loopback,10,1 \
OUTPUT_URL=hw:Loopback,10,0 \
SAMPLE_RATE=192000 \
./multiband_agc.sh
```

Note:
- This module is intentionally independent from Stereo Tool.
- You can chain it anywhere in your plumbing path where FFmpeg can read and write.

## Live Control Integration

The installer (`encoder/oMPX-Encoder-Debian-setup.sh`) can deploy an optional web control UI that applies live preview adjustments while exposing:
- waveform visualization (time-domain)
- spectrum/band visualization (frequency-domain)
- selected-channel patch preview in browser
- optional hardware patch output for local auditioning

The web UI can be restricted by bind address, port, and CIDR whitelist, with optional login authentication.
