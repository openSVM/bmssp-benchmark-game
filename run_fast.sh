#!/bin/bash
set -euo pipefail

# Fast native-only 1000x benchmark
OUTDIR="results-1000x-fast"
echo "Running fast 1000x benchmark (rust,c,cpp,nim only)..."
python3 bench/runner.py \
  --params bench/params_1000x.yaml \
  --shared-inputs \
  --include-impls rust,c,cpp,nim \
  --release \
  --jobs 1 \
  --timeout-seconds 3600 \
  --out "$OUTDIR"

echo "Fast benchmark complete. Results in $OUTDIR/"
