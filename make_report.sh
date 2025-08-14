#!/bin/bash
set -euo pipefail

# Generate plot and report from latest results
OUTDIR=${1:-"results-1000x-fast"}
echo "Generating artifacts for $OUTDIR..."

CSV=$(ls -1 "$OUTDIR"/agg-*.csv | tail -n1)
META=$(ls -1 "$OUTDIR"/meta-*.yaml 2>/dev/null | tail -n1 || true)

python3 bench/plots.py "$CSV" --out "$OUTDIR"
python3 bench/make_report.py --csv "$CSV" ${META:+--meta "$META"} --out "$OUTDIR"

echo "Generated:"
echo "  $OUTDIR/time_vs_popped.png"
echo "  $OUTDIR/REPORT.md"
