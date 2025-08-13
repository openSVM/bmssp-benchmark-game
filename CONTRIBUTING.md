# Contributing

Thanks for helping improve bmssp-benchmark-game! This project compares bounded multi-source SSSP across languages in a reproducible way.

## Adding a new language
- Create `impls/<lang>/` with a build script (Makefile, shards, etc.).
- Implement the CLI contract:
  - Flags: `--graph grid|er|ba`, `--rows/--cols` or `--n/--p`, `--k`, `--B`, `--seed`, `--trials`, `--maxw`, `--json`.
  - Output per trial: one JSON line with keys: impl, lang, graph, n, m, k, B, seed, time_ns, popped, edges_scanned, heap_pushes, B_prime, mem_bytes.
  - Use push-duplicates, skip-stale; halt when next pop >= B; track B'.
- Keep single-threaded and exclude graph generation from timed region.
- Add build + run hooks to `bench/runner.py` following existing implementations.

## Verification
- Ensure results match Rust’s metrics for the same seed and params on tiny graphs (popped, edges_scanned, B_prime).
- Run `python3 bench/runner.py --out results` locally.

## Code style
- Favor simplicity and portability over micro-optimizations. No global state.
- Add comments on any non-obvious choices.
