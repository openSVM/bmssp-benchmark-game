#!/usr/bin/env python3
import argparse, csv, pathlib, sys
from collections import defaultdict

try:
    import yaml
except Exception:
    yaml = None


def load_rows(csv_path):
    rows = []
    with open(csv_path) as f:
        r = csv.DictReader(f)
        for row in r:
            # coerce selected ints if present
            for k in ["time_ns","popped","edges_scanned","heap_pushes","B","k","seed","threads","n","m","B_prime","mem_bytes"]:
                if k in row and row[k] not in (None, ""):
                    try:
                        row[k] = int(row[k])
                    except Exception:
                        pass
            rows.append(row)
    return rows


def best_rows_by_impl(rows):
    # Choose the row with the largest 'popped' per (impl, lang, graph), tie-breaker: smallest time_ns
    best = {}
    for r in rows:
        key = (r.get('impl',''), r.get('lang',''), r.get('graph',''))
        prev = best.get(key)
        if prev is None:
            best[key] = r
        else:
            p_new = int(r.get('popped') or 0)
            p_old = int(prev.get('popped') or 0)
            if p_new > p_old or (p_new == p_old and int(r.get('time_ns') or 1<<62) < int(prev.get('time_ns') or 1<<62)):
                best[key] = r
    return list(best.values())


def format_md_table(rows):
    headers = ["impl","lang","graph","n","m","k","B","threads","time_ns","popped","edges_scanned","heap_pushes","B_prime","mem_bytes"]
    lines = []
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("|" + "---|"*len(headers))
    for r in sorted(rows, key=lambda x: (x.get('graph',''), x.get('lang',''))):
        vals = [str(r.get(h, '')) for h in headers]
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--csv', required=True)
    ap.add_argument('--meta', required=False)
    ap.add_argument('--out', required=True, help='output directory')
    args = ap.parse_args()

    outdir = pathlib.Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)
    rows = load_rows(args.csv)
    summary = best_rows_by_impl(rows)
    md = ["# BMSSP 1000x Report",""]
    if args.meta and yaml is not None:
        try:
            meta = yaml.safe_load(open(args.meta))
            md.append("Environment:")
            host = meta.get('host', {}) if isinstance(meta, dict) else {}
            md.append(f"- Host: {host.get('system','')}/{host.get('release','')} ({host.get('machine','')})")
            md.append(f"- CPU cores: {meta.get('cpu_cores','')}")
            md.append(f"- Git commit: {meta.get('git_commit','')}")
            md.append("")
        except Exception:
            pass
    md.append("## Best rows per implementation (largest explored set)")
    md.append("")
    md.append(format_md_table(summary))
    md_text = "\n".join(md) + "\n"
    (outdir/"REPORT.md").write_text(md_text)
    print(f"wrote {(outdir/'REPORT.md')}")


if __name__ == '__main__':
    main()
