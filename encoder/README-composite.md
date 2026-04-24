# oMPX Composite Encoder (Direct Mode)

## Usage

Build:

    cd /workspaces/oMPX/encoder
    make

Run (default PI=0x5717, PS="oMPX", RT from songtitle.txt):

    ./ompx-composite < input.pcm > composite.pcm

- To set PI code, PS, or RT file:

    ./ompx-composite 0x92EE WXPE mytitle.txt < input.pcm > composite.pcm

- The RT (RadioText) is read from the first 64 bytes of the file (default: songtitle.txt) and updates live.
- Output is FM composite (L+R, L−R, pilot, RDS) at 192kHz, 32-bit signed int.

## Integration
- This binary is now the default oMPX processor for stereo+RDS composite unless Stereo Tool is selected.
- VostokRadioLite remains available as an advanced/optional processor.
