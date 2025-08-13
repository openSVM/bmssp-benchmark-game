#!/usr/bin/env python3
import argparse, pathlib, csv
import matplotlib.pyplot as plt

def load_csv(path):
    rows=[]
    with open(path) as f:
        r = csv.DictReader(f)
        for row in r:
            row['time_ns'] = int(row['time_ns'])
            row['popped'] = int(row['popped'])
            rows.append(row)
    return rows

def plot_time_vs_popped(rows, outdir):
    by_lang = {}
    for r in rows:
        key = (r['impl'], r['lang'])
        by_lang.setdefault(key, []).append(r)
    plt.figure(figsize=(6,4))
    for (impl, lang), pts in by_lang.items():
        pts = sorted(pts, key=lambda x: x['popped'])
        xs = [p['popped'] for p in pts]
        ys = [p['time_ns']/1e6 for p in pts]
        plt.plot(xs, ys, marker='o', label=f"{lang} ({impl})")
    plt.xlabel('|U| popped')
    plt.ylabel('time (ms)')
    plt.title('BMSSP time vs |U|')
    plt.legend()
    out = pathlib.Path(outdir)/'time_vs_popped.png'
    plt.tight_layout()
    plt.savefig(out)
    print(f'wrote {out}')

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('csv')
    ap.add_argument('--out', default='results')
    args = ap.parse_args()
    rows = load_csv(args.csv)
    plot_time_vs_popped(rows, args.out)
