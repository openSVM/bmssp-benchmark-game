#!/usr/bin/env python3
import argparse, subprocess, json, sys, csv, pathlib, shutil, hashlib, platform, os, random
from concurrent.futures import ThreadPoolExecutor, as_completed
try:
    import yaml  # optional
except Exception:
    yaml = None
try:
    from jsonschema import Draft202012Validator as SchemaValidator
except Exception:
    SchemaValidator = None
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[1]


def cfg_key_blob(graph_cfg, k, seed, maxw):
    blob = json.dumps({'graph_cfg': graph_cfg, 'k': k, 'seed': seed, 'maxw': maxw}, sort_keys=True).encode('utf-8')
    return hashlib.sha256(blob).hexdigest()[:16]


def generate_shared_inputs(graph_cfg, k, seed, maxw, out_dir):
    """Generate canonical graph+sources files to ensure identical inputs across languages.
    Format:
      graph.txt: first line 'n m', followed by m lines 'u v w' (directed edges)
      sources.txt: first line 'k', followed by k lines 'u d0'
    Returns paths (graph_path, sources_path).
    """
    g = graph_cfg
    key = cfg_key_blob(graph_cfg, k, seed, maxw)
    idir = pathlib.Path(out_dir) / 'shared-inputs' / key
    graph_path = idir / 'graph.txt'
    src_path = idir / 'sources.txt'
    if graph_path.exists() and src_path.exists():
        return graph_path, src_path
    idir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(seed)
    edges = []
    n = 0
    gtype = g['type']
    if gtype == 'grid':
        rows, cols = int(g['rows']), int(g['cols'])
        n = rows * cols
        def idx(r,c):
            return r * cols + c
        for r in range(rows):
            for c in range(cols):
                u = idx(r,c)
                # down, right, up, left (directed, so both ways across iterations)
                if r + 1 < rows:
                    edges.append((u, idx(r+1,c), rng.randint(1, maxw)))
                if c + 1 < cols:
                    edges.append((u, idx(r, c+1), rng.randint(1, maxw)))
                if r - 1 >= 0:
                    edges.append((u, idx(r-1,c), rng.randint(1, maxw)))
                if c - 1 >= 0:
                    edges.append((u, idx(r, c-1), rng.randint(1, maxw)))
    elif gtype == 'er':
        n = int(g['n'])
        p = float(g['p'])
        if n > 200_000 and p * n > 10:
            print(f"[warn] ER graph with n={n} and p={p} will be extremely dense/heavy to generate (O(n^2)); consider BA/grid instead.", file=sys.stderr)
        for u in range(n):
            for v in range(n):
                if u == v: continue
                if rng.random() < p:
                    edges.append((u, v, rng.randint(1, maxw)))
    elif gtype == 'ba':
        n = int(g['n'])
        m0 = int(g.get('m0', 5))
        m_each = int(g.get('m', 5))
        ends = []
        start = max(1, min(m0, n))
        for u in range(start):
            for v in range(start):
                if u == v: continue
                edges.append((u, v, 1))
                ends.append(u)
        for u in range(start, n):
            for _ in range(m_each):
                if len(ends) == 0:
                    t = rng.randrange(0 if u == 0 else u or 1)
                else:
                    t = ends[rng.randrange(len(ends))]
                edges.append((u, t, rng.randint(1, maxw)))
                ends.append(t); ends.append(u)
    else:
        raise SystemExit(f'unsupported graph type for shared inputs: {gtype}')

    # write graph
    with open(graph_path, 'w') as f:
        f.write(f"{n} {len(edges)}\n")
        for (u,v,w) in edges:
            f.write(f"{u} {v} {w}\n")
    # sources: distinct k nodes, d0=0
    k_eff = int(k)
    chosen = set()
    srcs = []
    rng2 = random.Random(seed ^ 0x9E3779B97F4A7C15)
    while len(srcs) < k_eff and len(chosen) < n:
        s = rng2.randrange(n)
        if s not in chosen:
            chosen.add(s)
            srcs.append((s, 0))
    with open(src_path, 'w') as f:
        f.write(f"{len(srcs)}\n")
        for (s,d0) in srcs:
            f.write(f"{s} {d0}\n")
    return graph_path, src_path


def run_rust(graph_cfg, B, k, trials, seed, maxw, threads, bin_path, timeout_s=0, shared_inputs=None):
    args = [str(bin_path), '--json', '--trials', str(trials), '--k', str(k), '--B', str(B), '--seed', str(seed), '--maxw', str(maxw), '--threads', str(threads)]
    gtype = graph_cfg['type']
    if shared_inputs is not None:
        graph_path, src_path = shared_inputs
        args += ['--graph', gtype, '--graph-file', str(graph_path), '--sources-file', str(src_path)]
    else:
        args += ['--graph', gtype]
        if gtype == 'grid':
            args += ['--rows', str(graph_cfg['rows']), '--cols', str(graph_cfg['cols'])]
        elif gtype == 'er':
            args += ['--n', str(graph_cfg['n']), '--p', str(graph_cfg['p'])]
        elif gtype == 'ba':
            args += ['--n', str(graph_cfg['n']), '--m0', str(graph_cfg.get('m0',5)), '--m', str(graph_cfg.get('m',5))]
        else:
            raise SystemExit(f'unsupported graph type: {gtype}')

    try:
        p = subprocess.run(args, check=True, capture_output=True, text=True, timeout=(timeout_s or None))
    except subprocess.TimeoutExpired:
        print(f'[warn] rust run timed out: {args}', file=sys.stderr)
        return []
    rows = [json.loads(line) for line in p.stdout.splitlines() if line.strip()]
    for r in rows:
        r['graph_cfg'] = graph_cfg
    return rows

def build_crystal(root):
    crdir = root / 'impls' / 'crystal'
    # Prefer building if toolchain exists; otherwise fall back to prebuilt binary if present.
    bin_path = crdir / 'bin' / 'bmssp_cr'
    if shutil.which('crystal') and shutil.which('shards'):
        subprocess.run(['shards', 'build', '--release'], cwd=crdir, check=True)
        return bin_path
    # Fallback: use existing binary if available
    if bin_path.exists() and os.access(bin_path, os.X_OK):
        print('[info] Using prebuilt Crystal binary (compiler not found).', file=sys.stderr)
        return bin_path
    print('[warn] Crystal toolchain not found and no prebuilt binary present; skipping Crystal', file=sys.stderr)
    return None

def run_crystal(bin_path, graph_cfg, B, k, trials, seed, maxw, timeout_s=0):
    args = [str(bin_path), '--json', '--trials', str(trials), '--k', str(k), '--B', str(B), '--seed', str(seed), '--maxw', str(maxw)]
    gtype = graph_cfg['type']
    args += ['--graph', gtype]
    if gtype == 'grid':
        args += ['--rows', str(graph_cfg['rows']), '--cols', str(graph_cfg['cols'])]
    elif gtype == 'er':
        args += ['--n', str(graph_cfg['n']), '--p', str(graph_cfg['p'])]
    else:
        # Gracefully skip unsupported graph types for Crystal to avoid aborting smoke runs.
        print(f'[info] Crystal impl does not support graph type "{gtype}" yet; skipping', file=sys.stderr)
        return []
    try:
        p = subprocess.run(args, check=True, capture_output=True, text=True, timeout=(timeout_s or None))
    except subprocess.TimeoutExpired:
        print(f'[warn] crystal run timed out: {args}', file=sys.stderr)
        return []
    rows = [json.loads(line) for line in p.stdout.splitlines() if line.strip()]
    for r in rows:
        r['graph_cfg'] = graph_cfg
    return rows

def build_c(root):
    cdir = root / 'impls' / 'c'
    if not shutil.which('cc') and not shutil.which('gcc'):
        print('[warn] C compiler not found in PATH; skipping', file=sys.stderr)
        return None
    subprocess.run(['make'], cwd=cdir, check=True)
    return cdir / 'bmssp_c'

def run_c(bin_path, graph_cfg, B, k, trials, seed, maxw, timeout_s=0, shared_inputs=None):
    gtype = graph_cfg['type']
    args = [str(bin_path), '--k', str(k), '--B', str(B), '--seed', str(seed), '--trials', str(trials), '--maxw', str(maxw)]
    if shared_inputs is not None:
        graph_path, src_path = shared_inputs
        args += ['--graph', gtype, '--graph-file', str(graph_path), '--sources-file', str(src_path)]
    else:
        if gtype == 'grid':
            args += ['--graph','grid','--rows', str(graph_cfg['rows']), '--cols', str(graph_cfg['cols'])]
        elif gtype == 'er':
            args += ['--graph','er','--n', str(graph_cfg['n']), '--p', str(graph_cfg['p'])]
        elif gtype == 'ba':
            args += ['--graph','ba','--n', str(graph_cfg['n']), '--m0', str(graph_cfg.get('m0',5)), '--m', str(graph_cfg.get('m',5))]
        else:
            return []
    try:
        p = subprocess.run(args, check=True, capture_output=True, text=True, timeout=(timeout_s or None))
    except subprocess.TimeoutExpired:
        print(f'[warn] c run timed out: {args}', file=sys.stderr)
        return []
    rows = [json.loads(line) for line in p.stdout.splitlines() if line.strip()]
    for r in rows:
        r['graph_cfg'] = graph_cfg
    return rows

def build_cpp(root):
    d = root / 'impls' / 'cpp'
    if not shutil.which('c++') and not shutil.which('g++') and not shutil.which('clang++'):
        print('[warn] C++ compiler not found in PATH; skipping', file=sys.stderr)
        return None
    subprocess.run(['make'], cwd=d, check=True)
    return d / 'bmssp_cpp'

def run_cpp(bin_path, graph_cfg, B, k, trials, seed, maxw, timeout_s=0, shared_inputs=None):
    gtype = graph_cfg['type']
    args = [str(bin_path), '--k', str(k), '--B', str(B), '--seed', str(seed), '--trials', str(trials), '--maxw', str(maxw)]
    if shared_inputs is not None:
        graph_path, src_path = shared_inputs
        args += ['--graph', gtype, '--graph-file', str(graph_path), '--sources-file', str(src_path)]
    else:
        if gtype == 'grid':
            args += ['--graph','grid','--rows', str(graph_cfg['rows']), '--cols', str(graph_cfg['cols'])]
        elif gtype == 'er':
            args += ['--graph','er','--n', str(graph_cfg['n']), '--p', str(graph_cfg['p'])]
        elif gtype == 'ba':
            args += ['--graph','ba','--n', str(graph_cfg['n']), '--m0', str(graph_cfg.get('m0',5)), '--m', str(graph_cfg.get('m',5))]
        else:
            return []
    try:
        p = subprocess.run(args, check=True, capture_output=True, text=True, timeout=(timeout_s or None))
    except subprocess.TimeoutExpired:
        print(f'[warn] c++ run timed out: {args}', file=sys.stderr)
        return []
    rows = [json.loads(line) for line in p.stdout.splitlines() if line.strip()]
    for r in rows:
        r['graph_cfg'] = graph_cfg
    return rows

def build_kotlin(root):
    kdir = root / 'impls' / 'kotlin'
    kotlinc = shutil.which('kotlinc')
    java = shutil.which('java')
    # Fallback: SDKMAN default location
    if kotlinc is None:
        home = pathlib.Path.home()
        sdk_kotlinc = home / '.sdkman' / 'candidates' / 'kotlin' / 'current' / 'bin' / 'kotlinc'
        if sdk_kotlinc.exists():
            kotlinc = str(sdk_kotlinc)
    if java is None:
        print('[warn] Java (JDK) not found; skipping Kotlin', file=sys.stderr)
        return None
    if kotlinc is None:
        print('[warn] kotlinc not found; skipping Kotlin', file=sys.stderr)
        return None
    out = kdir / 'bmssp_kotlin.jar'
    src = kdir / 'src' / 'main' / 'kotlin' / 'Main.kt'
    subprocess.run([kotlinc, str(src), '-include-runtime', '-d', str(out)], cwd=kdir, check=True)
    return out

def run_kotlin(jar_path, graph_cfg, B, k, trials, seed, maxw, timeout_s=0):
    gtype = graph_cfg['type']
    args = ['java', '-jar', str(jar_path), '--json', '--trials', str(trials), '--k', str(k), '--B', str(B), '--seed', str(seed), '--maxw', str(maxw), '--graph', gtype]
    if gtype == 'grid':
        args += ['--rows', str(graph_cfg['rows']), '--cols', str(graph_cfg['cols'])]
    elif gtype == 'er':
        args += ['--n', str(graph_cfg['n']), '--p', str(graph_cfg['p'])]
    elif gtype == 'ba':
        args += ['--n', str(graph_cfg['n']), '--m0', str(graph_cfg.get('m0',5)), '--m', str(graph_cfg.get('m',5))]
    else:
        return []
    try:
        p = subprocess.run(args, check=True, capture_output=True, text=True, timeout=(timeout_s or None))
    except subprocess.TimeoutExpired:
        print(f'[warn] kotlin run timed out: {args}', file=sys.stderr)
        return []
    rows = [json.loads(line) for line in p.stdout.splitlines() if line.strip()]
    for r in rows:
        r['graph_cfg'] = graph_cfg
    return rows

def build_elixir(root):
    edir = root / 'impls' / 'elixir'
    if not shutil.which('elixir'):
        print('[warn] elixir not found in PATH; skipping', file=sys.stderr)
        return None
    # no build needed for .exs
    return edir / 'bmssp.exs'

def run_elixir(exs_path, graph_cfg, B, k, trials, seed, maxw, timeout_s=0):
    gtype = graph_cfg['type']
    if gtype == 'ba':
        # Elixir implementation currently lacks BA support; skip to avoid hard failures
        print(f"[info] Elixir impl does not support graph type \"{gtype}\" yet; skipping", file=sys.stderr)
        return []
    args = ['elixir', str(exs_path), '--trials', str(trials), '--k', str(k), '--B', str(B), '--seed', str(seed), '--maxw', str(maxw), '--graph', gtype]
    if gtype == 'grid':
        args += ['--rows', str(graph_cfg['rows']), '--cols', str(graph_cfg['cols'])]
    elif gtype == 'er':
        args += ['--n', str(graph_cfg['n']), '--p', str(graph_cfg['p'])]
    elif gtype == 'ba':
        # See above early return; keep branch for completeness if support is added later
        args += ['--n', str(graph_cfg['n']), '--m0', str(graph_cfg.get('m0',5)), '--m', str(graph_cfg.get('m',5))]
    else:
        return []
    try:
        p = subprocess.run(args, check=True, capture_output=True, text=True, timeout=(timeout_s or None))
    except subprocess.TimeoutExpired:
        print(f'[warn] elixir run timed out: {args}', file=sys.stderr)
        return []
    except subprocess.CalledProcessError as e:
        print(f'[warn] elixir run failed (exit {e.returncode}); skipping: {args}', file=sys.stderr)
        return []
    rows = [json.loads(line) for line in p.stdout.splitlines() if line.strip()]
    for r in rows:
        r['graph_cfg'] = graph_cfg
    return rows

def build_erlang(root):
    edir = root / 'impls' / 'erlang'
    if not shutil.which('erlc'):
        print('[warn] erlang compiler (erlc) not found; skipping', file=sys.stderr)
        return None
    subprocess.run(['erlc', 'bmssp.erl'], cwd=edir, check=True)
    return edir / 'bmssp.beam'

def run_erlang(beam_path, graph_cfg, B, k, trials, seed, maxw, timeout_s=0):
    gtype = graph_cfg['type']
    if gtype == 'ba':
        print(f"[info] Erlang impl does not support graph type \"{gtype}\" yet; skipping", file=sys.stderr)
        return []
    args = ['erl', '-noshell', '-pa', str(beam_path.parent), '-s', 'bmssp', 'main', '-s', 'init', 'stop', '-extra', '--trials', str(trials), '--k', str(k), '--B', str(B), '--seed', str(seed), '--maxw', str(maxw), '--graph', gtype]
    if gtype == 'grid':
        args += ['--rows', str(graph_cfg['rows']), '--cols', str(graph_cfg['cols'])]
    elif gtype == 'er':
        args += ['--n', str(graph_cfg['n']), '--p', str(graph_cfg['p'])]
    elif gtype == 'ba':
        args += ['--n', str(graph_cfg['n']), '--m0', str(graph_cfg.get('m0',5)), '--m', str(graph_cfg.get('m',5))]
    else:
        return []
    try:
        p = subprocess.run(args, check=True, capture_output=True, text=True, timeout=(timeout_s or None))
    except subprocess.TimeoutExpired:
        print(f'[warn] erlang run timed out: {args}', file=sys.stderr)
        return []
    except subprocess.CalledProcessError as e:
        print(f'[warn] erlang run failed (exit {e.returncode}); skipping: {args}', file=sys.stderr)
        return []
    rows = [json.loads(line) for line in p.stdout.splitlines() if line.strip()]
    for r in rows:
        r['graph_cfg'] = graph_cfg
    return rows

def build_nim(root):
    ndir = root / 'impls' / 'nim'
    if not shutil.which('nim'):
        print('[warn] Nim compiler not found in PATH; skipping', file=sys.stderr)
        return None
    subprocess.run(['nim', 'c', '-d:release', '--out:bmssp_nim', 'src/main.nim'], cwd=ndir, check=True)
    return ndir / 'bmssp_nim'

def run_nim(bin_path, graph_cfg, B, k, trials, seed, maxw, timeout_s=0):
    gtype = graph_cfg['type']
    args = [str(bin_path), '--k', str(k), '--B', str(B), '--seed', str(seed), '--trials', str(trials), '--maxw', str(maxw)]
    if gtype == 'grid':
        args += ['--graph','grid','--rows', str(graph_cfg['rows']), '--cols', str(graph_cfg['cols'])]
    elif gtype == 'er':
        args += ['--graph','er','--n', str(graph_cfg['n']), '--p', str(graph_cfg['p'])]
    elif gtype == 'ba':
        args += ['--graph','ba','--n', str(graph_cfg['n']), '--m0', str(graph_cfg.get('m0',5)), '--m', str(graph_cfg.get('m',5))]
    else:
        return []
    try:
        p = subprocess.run(args, check=True, capture_output=True, text=True, timeout=(timeout_s or None))
    except subprocess.TimeoutExpired:
        print(f'[warn] nim run timed out: {args}', file=sys.stderr)
        return []
    rows = [json.loads(line) for line in p.stdout.splitlines() if line.strip()]
    for r in rows:
        r['graph_cfg'] = graph_cfg
    return rows


def default_cfg():
    return {
        'graphs': [
            { 'type': 'grid', 'rows': 50, 'cols': 50 },
            { 'type': 'er', 'n': 5000, 'p': 0.0008 },
            { 'type': 'ba', 'n': 5000, 'm0': 5, 'm': 5 },
        ],
        'bounds': [25, 50, 100, 200],
        'sources_k': [4, 16],
        'trials': 5,
        'seed': 42,
        'maxw': 100,
        'threads': [1],
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--params', default=str(ROOT / 'bench' / 'params.yaml'))
    ap.add_argument('--out', default=str(ROOT / 'results'))
    ap.add_argument('--release', action='store_true')
    ap.add_argument('--timeout-seconds', type=float, default=0.0, help='per-process timeout (0 = no timeout)')
    ap.add_argument('--quick', action='store_true', help='run a minimal matrix for fast iteration')
    ap.add_argument('--jobs', type=int, default=1, help='parallel jobs for non-Rust implementations')
    ap.add_argument('--smoke', action='store_true', help='use bench/smoke_matrix.yaml and enforce basic invariants')
    ap.add_argument('--parity', action='store_true', help='check simple cross-impl parity on grid graphs')
    ap.add_argument('--shared-inputs', action='store_true', help='use canonical shared graph+sources files for supported implementations')
    ap.add_argument('--include-impls', default='', help='comma-separated list of impl keys to include (rust,c,cpp,kotlin,crystal,elixir,erlang,nim)')
    ap.add_argument('--exclude-impls', default='', help='comma-separated list of impl keys to exclude')
    args = ap.parse_args()

    # build
    if args.release:
        subprocess.run(['cargo', 'build', '--release', '-p', 'bmssp'], cwd=ROOT, check=True)
        rust_bin = ROOT / 'target' / 'release' / 'bmssp-cli'
    else:
        subprocess.run(['cargo', 'build', '-p', 'bmssp'], cwd=ROOT, check=True)
        rust_bin = ROOT / 'target' / 'debug' / 'bmssp-cli'

    # Impl filters
    all_keys = {'rust','c','cpp','kotlin','crystal','elixir','erlang','nim'}
    inc = set(x.strip() for x in args.include_impls.split(',') if x.strip()) or set(all_keys)
    exc = set(x.strip() for x in args.exclude_impls.split(',') if x.strip())
    sel = (inc & all_keys) - exc

    crystal_bin = None
    try:
        if 'crystal' in sel:
            crystal_bin = build_crystal(ROOT)
    except Exception as e:
        print(f'[warn] crystal build skipped: {e}', file=sys.stderr)
    c_bin = None
    try:
        if 'c' in sel:
            c_bin = build_c(ROOT)
    except Exception as e:
        print(f'[warn] c build skipped: {e}', file=sys.stderr)
    cpp_bin = None
    try:
        if 'cpp' in sel:
            cpp_bin = build_cpp(ROOT)
    except Exception as e:
        print(f'[warn] cpp build skipped: {e}', file=sys.stderr)
    kotlin_jar = None
    try:
        if 'kotlin' in sel:
            kotlin_jar = build_kotlin(ROOT)
    except Exception as e:
        print(f'[warn] kotlin build skipped: {e}', file=sys.stderr)
    elixir_exs = None
    try:
        if 'elixir' in sel:
            elixir_exs = build_elixir(ROOT)
    except Exception as e:
        print(f'[warn] elixir build skipped: {e}', file=sys.stderr)
    erlang_beam = None
    try:
        if 'erlang' in sel:
            erlang_beam = build_erlang(ROOT)
    except Exception as e:
        print(f'[warn] erlang build skipped: {e}', file=sys.stderr)
    nim_bin = None
    try:
        if 'nim' in sel:
            nim_bin = build_nim(ROOT)
    except Exception as e:
        print(f'[warn] nim build skipped: {e}', file=sys.stderr)

    if yaml is not None:
        try:
            if args.smoke and (ROOT / 'bench' / 'smoke_matrix.yaml').exists():
                cfg = yaml.safe_load(open(ROOT / 'bench' / 'smoke_matrix.yaml'))
            else:
                cfg = yaml.safe_load(open(args.params))
        except Exception:
            cfg = default_cfg()
    else:
        cfg = default_cfg()
    if args.quick:
        cfg = {
            'graphs': [ { 'type': 'grid', 'rows': 50, 'cols': 50 } ],
            'bounds': [50],
            'sources_k': [4],
            'trials': 1,
            'seed': cfg.get('seed', 42),
            'maxw': cfg.get('maxw', 100),
            'threads': [1],
        }
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')

    # Load schema validator (optional)
    validator = None
    schema_path = ROOT / 'bench' / 'schema.json'
    if SchemaValidator is not None and schema_path.exists():
        try:
            schema = json.loads(schema_path.read_text())
            validator = SchemaValidator(schema)
        except Exception as e:
            print(f'[warn] could not load schema: {e}', file=sys.stderr)

    all_rows = []
    invalid_rows = 0
    invariant_violations = 0
    parity_issues = 0
    threads_list = cfg.get('threads', [1])
    def maybe_validate_and_add(rows):
        nonlocal invalid_rows, invariant_violations
        for r in rows:
            if 'threads' not in r:
                r['threads'] = 1
            if validator is not None:
                try:
                    validator.validate(r)
                except Exception as e:
                    invalid_rows += 1
                    print(f'[warn] invalid row skipped: {e}', file=sys.stderr)
                    continue
            if args.smoke:
                ok = True
                if not (r.get('time_ns', 0) > 0): ok = False
                if not (r.get('popped', 0) >= 0): ok = False
                if 'B' in r and 'B_prime' in r and r['B_prime'] < r['B']: ok = False
                if r.get('m', 0) < 0: ok = False
                if not ok:
                    invariant_violations += 1
                    print(f"[warn] invariant failed for row: impl={r.get('impl')} graph={r.get('graph')}", file=sys.stderr)
                    continue
            all_rows.append(r)

    try:
        for g in cfg['graphs']:
            for B in cfg['bounds']:
                for k in cfg['sources_k']:
                    # Rust: run serially across thread counts to avoid CPU contention
                    if 'rust' in sel:
                        for th in threads_list:
                            shared = None
                            if args.shared_inputs:
                                shared = generate_shared_inputs(g, k, cfg['seed'], cfg['maxw'], out_dir)
                            rows = run_rust(g, B, k, cfg['trials'], cfg['seed'], cfg['maxw'], th, rust_bin, timeout_s=args.timeout_seconds, shared_inputs=shared)
                            maybe_validate_and_add(rows)

                    # Prepare non-Rust tasks
                    tasks = []
                    if 'crystal' in sel and crystal_bin is not None:
                        # Crystal: no shared-input support yet
                        tasks.append((run_crystal, (crystal_bin, g, B, k, cfg['trials'], cfg['seed'], cfg['maxw'], args.timeout_seconds)))
                    if 'c' in sel and c_bin is not None:
                        shared = None
                        if args.shared_inputs:
                            shared = generate_shared_inputs(g, k, cfg['seed'], cfg['maxw'], out_dir)
                        tasks.append((run_c, (c_bin, g, B, k, cfg['trials'], cfg['seed'], cfg['maxw'], args.timeout_seconds, shared)))
                    if 'cpp' in sel and cpp_bin is not None:
                        shared = None
                        if args.shared_inputs:
                            shared = generate_shared_inputs(g, k, cfg['seed'], cfg['maxw'], out_dir)
                        tasks.append((run_cpp, (cpp_bin, g, B, k, cfg['trials'], cfg['seed'], cfg['maxw'], args.timeout_seconds, shared)))
                    if 'kotlin' in sel and kotlin_jar is not None:
                        tasks.append((run_kotlin, (kotlin_jar, g, B, k, cfg['trials'], cfg['seed'], cfg['maxw'], args.timeout_seconds)))
                    if 'elixir' in sel and elixir_exs is not None:
                        tasks.append((run_elixir, (elixir_exs, g, B, k, cfg['trials'], cfg['seed'], cfg['maxw'], args.timeout_seconds)))
                    if 'erlang' in sel and erlang_beam is not None:
                        tasks.append((run_erlang, (erlang_beam, g, B, k, cfg['trials'], cfg['seed'], cfg['maxw'], args.timeout_seconds)))
                    if 'nim' in sel and nim_bin is not None:
                        tasks.append((run_nim, (nim_bin, g, B, k, cfg['trials'], cfg['seed'], cfg['maxw'], args.timeout_seconds)))

                    if tasks:
                        if args.jobs <= 1:
                            for func, pargs in tasks:
                                try:
                                    rows = func(*pargs)
                                except Exception as e:
                                    print(f'[warn] task failed: {e}', file=sys.stderr)
                                    rows = []
                                maybe_validate_and_add(rows)
                        else:
                            with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
                                futs = [ex.submit(func, *pargs) for func, pargs in tasks]
                                for fut in as_completed(futs):
                                    try:
                                        rows = fut.result()
                                    except Exception as e:
                                        print(f'[warn] task failed: {e}', file=sys.stderr)
                                        rows = []
                                    maybe_validate_and_add(rows)
    except KeyboardInterrupt:
        # Graceful: write partial files with -partial suffix
        stamp_part = stamp + '-partial'
        jsonl = out_dir / f'raw-{stamp_part}.jsonl'
        with open(jsonl, 'w') as f:
            for r in all_rows:
                f.write(json.dumps(r) + '\n')
        csv_path = out_dir / f'agg-{stamp_part}.csv'
        keys = ['impl', 'lang', 'graph', 'n', 'm', 'k', 'B', 'seed', 'threads', 'time_ns', 'popped', 'edges_scanned', 'heap_pushes', 'B_prime', 'mem_bytes']
        with open(csv_path, 'w', newline='') as f:
            w = csv.writer(f)
            w.writerow(keys)
            for r in all_rows:
                w.writerow([r.get(k) for k in keys])
        print(f'[info] Interrupted. Wrote partial outputs: {jsonl} and {csv_path}', file=sys.stderr)
        return

    # write jsonl and csv
    jsonl = out_dir / f'raw-{stamp}.jsonl'
    with open(jsonl, 'w') as f:
        for r in all_rows:
            f.write(json.dumps(r) + '\n')

    csv_path = out_dir / f'agg-{stamp}.csv'
    keys = ['impl', 'lang', 'graph', 'n', 'm', 'k', 'B', 'seed', 'threads', 'time_ns', 'popped', 'edges_scanned', 'heap_pushes', 'B_prime', 'mem_bytes']
    with open(csv_path, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(keys)
        for r in all_rows:
            # default threads to 1 if not present
            if 'threads' not in r:
                r['threads'] = 1
            # Normalize impl key (some emit 'impl' already; Rust uses serde rename)
            if 'impl' not in r and 'impl_' in r:
                r['impl'] = r.get('impl_')
            w.writerow([r.get(k) for k in keys])

    # Metadata file
    try:
        host = platform.uname()._asdict() if hasattr(platform.uname(), '_asdict') else {
            'system': platform.system(), 'release': platform.release(), 'machine': platform.machine()
        }
    except Exception:
        host = {}
    try:
        commit = subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
    except Exception:
        commit = ''
    params_blob = json.dumps(cfg, sort_keys=True).encode('utf-8')
    params_hash = hashlib.sha256(params_blob).hexdigest()[:16]
    meta = {
        'stamp': stamp,
        'host': host,
        'cpu_cores': os.cpu_count(),
        'git_commit': commit,
        'params_hash': params_hash,
        'params': cfg,
        'rows': len(all_rows),
        'invalid_rows_skipped': invalid_rows,
        'invariant_violations': invariant_violations,
        'parity_issues': 0,
    }
    # Optional parity check: only for grid graphs, verify n/m consistency across implementations per config
    if args.parity:
        try:
            from collections import defaultdict
            groups = defaultdict(list)
            for r in all_rows:
                gc = r.get('graph_cfg') or {}
                if r.get('graph') == 'grid' and isinstance(gc, dict):
                    key = (gc.get('rows'), gc.get('cols'), r.get('B'), r.get('k'))
                    groups[key].append(r)
            for key, rows in groups.items():
                ns = {r.get('n') for r in rows}
                ms = {r.get('m') for r in rows}
                if len(ns) > 1 or len(ms) > 1:
                    parity_issues += 1
                    print(f"[warn] parity mismatch for grid{key}: n={ns}, m={ms}", file=sys.stderr)
        except Exception as e:
            print(f"[warn] parity check failed: {e}", file=sys.stderr)
        meta['parity_issues'] = parity_issues
    meta_path = out_dir / f'meta-{stamp}.yaml'
    try:
        if yaml is not None:
            with open(meta_path, 'w') as f:
                yaml.safe_dump(meta, f, sort_keys=False)
        else:
            with open(meta_path, 'w') as f:
                f.write(json.dumps(meta, indent=2))
    except Exception as e:
        print(f'[warn] failed to write metadata: {e}', file=sys.stderr)

    print(f'Wrote {jsonl}, {csv_path}, and {meta_path}')
    if invalid_rows or invariant_violations or parity_issues:
        print(f"[info] skipped rows — schema: {invalid_rows}, invariants: {invariant_violations}, parity: {parity_issues}", file=sys.stderr)

if __name__ == '__main__':
    main()
