# oMPX
open source dual channel FM Multiplex network transport with Stereo, RDS and SCA support using 192khz FreeLosslessAudioCodec

## Modules

Additional processing modules live in [modules/README.md](modules/README.md).

Current module:
- [modules/multiband_agc.sh](modules/multiband_agc.sh): 3-band compressor + AGC + limiter pipeline using FFmpeg.

## Live Web Control UI

The installer now supports an optional oMPX web control service with:
- live channel patch preview from selected ALSA capture endpoint
- real-time waveform and frequency-band visualizers in browser
- patch monitoring to local audio hardware output (optional)
- configurable bind IP, port, and CIDR whitelist (Stereo Tool style workflow)
- optional login authentication (username/password)

This is configured in:
- `encoder/oMPX-Encoder-Debian-setup.sh`

Runtime defaults:
- service: `ompx-web-ui.service`
- default bind: `0.0.0.0`
- default port: `8082`

