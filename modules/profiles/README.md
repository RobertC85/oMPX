# External Profiles

Drop `.env` files in this folder to create custom profiles for `multiband_agc.sh`.

Usage:
- `./multiband_agc.sh --profile my-profile`
- `./multiband_agc.sh --profile-dir /custom/path --profile my-profile`

File format:
- One `KEY=VALUE` assignment per line.
- Use shell-style quoting for values with spaces or `|` characters.
- Any variable from `multiband_agc.sh` can be overridden.
- Optional inheritance: set `BASE_PROFILE=<name>` to start from another built-in or external profile.

Inheritance example:
```bash
BASE_PROFILE=decoder-clean
BAND3_TRIM_DB=1.0
HF_TAME_DB=-1.8
```

Common variables:
- `XOVER_1`, `XOVER_2`, `XOVER_3`, `XOVER_4`
- `BAND1_COMPAND` ... `BAND5_COMPAND`
- `AGC_FILTER`, `OUTPUT_LIMIT`
- `HPF_FREQ`, `LPF_FREQ`
- `PRE_GAIN_DB`, `POST_GAIN_DB`
- `PARALLEL_DRY_MIX`, `STEREO_WIDTH`
- `HF_TAME_DB`, `HF_TAME_FREQ`
