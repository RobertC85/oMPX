#!/usr/bin/env bash
set -euo pipefail

cd /workspaces/oMPX/encoder

# Generate test PCM if not present
if [ ! -f input.pcm ]; then
  echo "Generating input.pcm..."
  python3 ../VostokRadioLite/test_pcm_gen.py
  mv ../VostokRadioLite/test_stereo.pcm input.pcm
fi

# Create a default RT file
if [ ! -f songtitle.txt ]; then
  echo "Test RadioText for oMPX composite encoder." > songtitle.txt
fi

# Build if needed
make

# Run the composite encoder
./ompx-composite < input.pcm > composite.pcm

echo "Done. Output: composite.pcm (FM composite with stereo+RDS)"
