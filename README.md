# oMPX
open source dual channel FM Multiplex network transport with Stereo, RDS and SCA support using 192khz FreeLosslessAudioCodec

## Modules

Additional processing modules live in [modules/README.md](modules/README.md).

Current module:
- [modules/multiband_agc.sh](modules/multiband_agc.sh): 3-band compressor + AGC + limiter pipeline using FFmpeg.


## Dependencies

You must have Liquidsoap installed for all processing and preview services to work:

- Install on Debian/Ubuntu:
	sudo apt-get update && sudo apt-get install liquidsoap

Liquidsoap is required for:
- Main processing (ompx-processing.liq)
- Preview processing (ompx-preview.liq)
- All real-time audio streaming and preview endpoints

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

## RDS Metadata Sidecar

When Program 1/2 RDS sync is enabled, the installer now also writes sidecar JSON files:
- `/home/ompx/rds/prog1/rds-info.json`
- `/home/ompx/rds/prog2/rds-info.json`

Each sidecar includes adjustable RDS fields:
- `ps`, `pi`, `pty`, `tp`, `ta`, `ms`
- `ct` (clock time; local or UTC mode)
- `rt` (current RadioText)

These values are configured in the installer RDS dialog and persisted in `/home/ompx/.profile`.

## Uninstall and User Deletion Behavior

- The uninstall script supports destructive flags: --nuke, --nuke-packages, and --scorch.
- 🚨🚨🚨 **EXTREME DANGER: --scorch will PERMANENTLY and IRREVERSIBLY DELETE ALL oMPX, NGINX, ICECAST, LIQUIDSOAP, ALSA, AND RELATED FILES, CONFIGS, LOGS, USERS (INCLUDING HOME DIRECTORIES), AND DISABLE/REMOVE ALL RELATED SERVICES. THIS WILL BREAK LOGINS, REMOVE USER DATA, AND CAN LEAVE YOUR SYSTEM UNUSABLE. THERE IS ABSOLUTELY NO UNDO. DO NOT USE --scorch UNLESS YOU FULLY UNDERSTAND THE CONSEQUENCES.** 🚨🚨🚨
- If run as the ompx user, uninstall is blocked for safety unless --scorch and --kill-ompx-user are both specified.
- With --scorch (as ompx), only the home directory is deleted; the user account remains, so SSH is still possible but without a home directory.
- With --scorch --kill-ompx-user (as ompx), both the home directory and the user account are deleted, fully disabling SSH for ompx.
- **If you run the installer again after a --scorch, it will attempt to automatically repair and reinstall all missing users, packages, and configs.**
- This prevents accidental lockout and ensures you can only self-destruct the ompx user with explicit intent.

