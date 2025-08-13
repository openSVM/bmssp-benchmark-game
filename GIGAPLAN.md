# GIGAPLAN — BMSSP Benchmark Suite Execution Plan

Date: 2025-08-12
Owner: repo maintainers
Scope: End-to-end benchmarking “bmssp-benchmark-game” with multi-language implementations, reproducible graphs, automated runners, CI, plotting, and installers.

This plan is decomposed into atomic tasks with clear inputs/outputs, concrete steps, acceptance criteria, and dependencies. Use it as the source of truth for driving the remaining work to done.

---

## 0) Current status snapshot (truth as of 2025-08-12)
- Baseline (Rust):
  - CLI supports grid/er/ba, JSON, threads, trials, seed, maxw. Multithreaded sharded variant behind `--threads`.
  - Metrics: time_ns, popped, edges_scanned, heap_pushes, B_prime, mem_bytes.
- Runner (Python):
  - Builds Rust, C, C++, Crystal, Nim; Kotlin/Elixir/Erlang are optional and skipped if toolchains missing.
  - Supports graph configs from YAML, including threads for Rust; writes JSONL and CSV aggregates.
  - BA graph now wired for Rust and all supported languages; non-fatal toolchain skips.
- Implementations present: Rust, C, C++, Nim, Crystal, Kotlin, Elixir, Erlang. Zig removed (tombstone in impls/zig/README.removed).
- Installers: Bash + PowerShell. CI: GitHub Actions on Ubuntu; installs toolchains, runs runner, uploads artifacts.

Gaps/risks:
- Kotlin/Elixir/Erlang toolchains may not always be available on ubuntu-latest; add robust fallbacks.
- Runner lacks timeouts and graceful Ctrl-C persistence; long jobs can be interrupted.
- Linux installer script still contains Zig logic (should be removed); ensure docs reflect Zig removal.
- Limited tests/smoke checks across all languages; need schema validation and CLI sanity tests.

---

## 1) Global contracts and conventions

- JSON schema (all languages must emit per-run JSON line):
  - Keys: `impl, lang, graph, n, m, k, B, seed, time_ns, popped, edges_scanned, heap_pushes, B_prime, mem_bytes` (+ `threads` where applicable; default 1 in CSV aggregator).
- CLI arg contract (shared semantics):
  - `--json` (no-op in some langs), `--trials`, `--k`, `--B`, `--seed`, `--maxw`, `--graph {grid|er|ba}`, and graph-specific: grid(`--rows --cols`), er(`--n --p`), ba(`--n --m0 --m`).
- Graph RNG and seeds:
  - Use language-native RNG seeded with `seed + trial_index`; ensure weights in [1..=maxw].
- Algorithmic behavior (BMSSP):
  - Dijkstra variant with push-duplicates, skip-stale; stop at first pop ≥ B and record B′; track edges scanned and heap pushes.

Deliverables:
- bench/schema.json (JSON Schema v2020-12) for validation.
- Spec page in README and link from each impl README.

---

## 2) Runner orchestration improvements

T-2001 Add per-process timeout and graceful interrupt
- Inputs: bench/runner.py
- Steps:
  - Add `--timeout-seconds` (default: 0 = no timeout). For each subprocess.run, pass timeout and catch TimeoutExpired -> log warning, skip row, continue.
  - Trap KeyboardInterrupt in main() -> flush accumulated rows to JSONL/CSV with partial stamp `-partial` suffix.
- Acceptance:
  - Ctrl-C mid-run produces JSONL/CSV with at least the rows completed.
  - Timeout on any impl logs warning and continues the matrix.

T-2002 Add `--quick` preset for faster iteration
- Steps:
  - Add CLI flag that overrides params to a minimal set (e.g., 1 graph, bounds [50], sources_k [4], trials 1, threads [1]).
  - Document in README.
- Acceptance: `python3 bench/runner.py --quick` writes outputs < 20s on a typical laptop.

T-2003 Schema validation and CSV typing
- Steps:
  - Create `bench/schema.json` and a tiny validator step (jsonschema) to validate each parsed line before aggregation; invalid rows logged and skipped.
  - Ensure CSV writes `threads=1` when missing.
- Acceptance: Invalid rows don’t break the run; count of skipped rows reported at end.

T-2004 Parallel execution control
- Steps:
  - Add `--jobs N` to run independent language invocations in parallel (multiprocessing Pool) per matrix point; Rust threads loop remains serial to control CPU contention.
  - Global process cap via semaphore.
- Acceptance: With `--jobs 2`, wall time decreases vs serial on multi-core machine.

T-2005 Deterministic stamping and metadata
- Steps:
  - Add a `meta` header row (YAML) next to JSONL/CSV with host info (uname, CPU cores), git commit, and params hash.
- Acceptance: Results folder contains `meta-<stamp>.yaml` with filled fields.

---

## 3) Implementations parity and tests (by language)

Common acceptance for each language L:
- Supports grid/er/ba, honors k/B/seed/trials/maxw args, outputs valid JSON per schema, runs a smoke test quickly.
- Provide a minimal README with build/run commands and flags mapping.

T-3100 Rust parity checks (bmssp/)
- Steps:
  - Unit tests: graph builders (grid, er, ba), bmssp vs bmssp_sharded equivalence on small graphs.
  - Add `--er-directed` optional flag to align with directed ER used in Rust (confirm current behavior: Rust ER builder adds directed edges; document).
- Acceptance: `cargo test -p bmssp` passes; small ER/BA sanity checks.

T-3200 C implementation audit
- Steps:
  - Verify BA support is implemented and compatible: args `--graph ba --n --m0 --m`.
  - Ensure JSON keys match and seed usage is reproducible.
  - Add `make smoke` target running a tiny graph.
- Acceptance: `make && ./bmssp_c --graph grid --rows 4 --cols 4 --k 2 --B 5 --trials 1 --seed 1 --maxw 5` emits valid JSON.

T-3300 C++ implementation audit
- Same as C; add a README with std::mt19937 seeding.

T-3400 Nim implementation audit
- Steps: Confirm ER/BA generators and JSON schema; add `nimble test` or a script for smoke.

T-3500 Crystal implementation audit
- Steps: Ensure shards.lock present; provide `shards build --release` path; smoke script.

T-3600 Kotlin implementation audit
- Steps:
  - Validate BA generator and PriorityQueue relaxations; confirm `--json` flag accepted/no-op.
  - Ensure fat-jar output `bmssp_kotlin.jar`; add a small Gradle or keep kotlinc (document both).
  - Smoke: `java -jar bmssp_kotlin.jar --graph grid --rows 4 --cols 4 ...`.

T-3700 Elixir implementation audit
- Steps:
  - Ensure :rand seeding with `:exs1024` per trial; BA preferential attachment works; JSON string escapes safe.
  - Smoke: `elixir bmssp.exs --graph er --n 100 --p 0.01 ...`.

T-3800 Erlang implementation audit
- Steps:
  - `erlc bmssp.erl` to .beam; confirm BA generator and gb_sets usage; verify output format on `erl -noshell` pipeline.

T-3900 Cross-language parity tests
- Steps:
  - Add `bench/smoke_matrix.yaml` with tiny configs. Python runner gains `--smoke` to run it and check schema + basic invariants: `popped > 0`, `time_ns > 0`, `B_prime >= B`, `m >= 0`.
- Acceptance: All installed languages pass smoke.

---

## 4) Installers (scripts/install_deps.sh, scripts/Install-Dependencies.ps1)

T-4001 Remove Zig from Linux/macOS installer
- Steps: Delete Zig section and summary lines; keep Kotlin/Elixir/Erlang; verify idempotent re-run.
- Acceptance: No Zig mentions; script succeeds.

T-4002 Kotlin/Java fallback installers for CI parity
- Steps: If `kotlinc` not in APT, fall back to SDKMAN or official tarball; append to PATH.
- Acceptance: `kotlinc -version` works locally and in CI runner.

T-4003 BEAM (Erlang/Elixir) robustness
- Steps: Add distro-specific repos if needed (e.g., Erlang Solutions) when stock packages are too old; guarded by opt-in flag.

T-4004 PEP 668 resilience (Python user installs)
- Steps: Already handled with `--break-system-packages`; document in script comments; ensure no hard fails.

---

## 5) CI/CD (GitHub Actions)

T-5001 Ensure Kotlin availability on ubuntu-latest
- Steps: If `sudo apt-get install kotlin` fails, use SDKMAN step to install JDK+Kotlin; cache ~/.sdkman.
- Acceptance: `kotlinc -version` in CI logs.

T-5002 Add a quick smoke workflow
- Steps: New job `smoke` runs `python3 bench/runner.py --quick` and uploads results; runs on PRs.

T-5003 Matrix or staged builds
- Steps: Optionally split language builds into separate steps with continue-on-error to isolate failures and still collect partial results.

T-5004 Caches for Crystal, Nim, BEAM
- Steps: Add cache dirs if beneficial (Crystal shards, Nimble; Erlang/Elixir not usually cached).

T-5005 Scheduled benchmark runs (optional)
- Steps: Add cron schedule (weekly) to run full suite and publish artifact.

---

## 6) Data, plots, documentation

T-6001 Plots
- Steps: Ensure bench/plots.py consumes agg CSV; add example commands and generated figure saved to results.
- Acceptance: PNG/SVG plots produced with legend and error bars if trials>1.

T-6002 Documentation refresh
- Steps: Update README to reflect languages (Kotlin/Elixir/Erlang), how to run quick vs full, installers, CI expectations, and troubleshooting.

T-6003 Results cataloging
- Steps: Add `results/README.md` describing file naming, metadata, and reproducibility notes.

---

## 7) Performance and correctness extras

T-7001 Add optional timeouts to BMSSP per impl (defensive)
- Steps: Not typical for CPU-bound; rely on runner timeouts. Document.

T-7002 Multithreading beyond Rust (stretch)
- Steps: Explore Kotlin coroutines/thread pools; Elixir/Erlang processes with ETS; document expected overhead.

T-7003 Memory accounting harmonization
- Steps: Provide a simple heuristic formula across languages; document caveats.

T-7004 Directed vs undirected ER parity
- Steps: Decide canonical: directed or undirected. Update all languages consistently; document in README and runner.

---

## 8) Repo hygiene and DX

T-8001 Pre-commit hooks (optional)
- Steps: Add basic formatting/lint hooks (rustfmt/clippy as tasks, black/isort for bench, shellcheck for scripts) but keep simple.

T-8002 CONTRIBUTING.md and CODEOWNERS
- Steps: Light guidance for adding new language implementations and schema adherence.

T-8003 License confirmation
- Steps: Ensure LICENSE present and referenced in READMEs.

---

## 9) Work plan, order of operations (suggested)
1) Runner resilience (T-2001, T-2002, T-2003) — unblock iteration and CI stability.
2) Installer cleanup (T-4001) — remove Zig; toolchain fallbacks (T-4002).
3) CI Kotlin fallback (T-5001) + smoke job (T-5002).
4) Language parity audits (T-3100..T-3900) in parallel.
5) Docs and plots (T-6001..T-6003).
6) Optional performance/stretch items (T-7002..).

---

## 10) Acceptance checklist (high level)
- [ ] Runner: timeouts, graceful interrupt, quick mode, schema validation.
- [ ] All languages installed (when requested) or gracefully skipped; smoke matrix passes for installed ones.
- [ ] CI: quick job green on PRs; full job green on main with artifacts.
- [ ] README/docs reflect current stack; installers are Zig-free and idempotent.
- [ ] Plots produced from latest results; metadata present.

---

## 11) Concrete command hints (for implementers)
Note: Commands are examples for implementers; the runner and CI will execute the canonical flows.

- Run quick smoke locally:
  - `python3 bench/runner.py --quick`
- Run full release build locally:
  - `python3 bench/runner.py --release --out results`
- Validate schema locally (to be added in T-2003):
  - `python3 -m pip install jsonschema && python3 -m jsonschema -i results/raw-*.jsonl bench/schema.json`

---

## 12) Known issues to track
- Directed ER in Rust vs undirected in some other impls; finalize convention (T-7004).
- Installer (Linux) still contains Zig section — remove fully (T-4001).
- CI kotlin availability may vary; SDKMAN fallback required (T-5001).

---

## 13) Change log for this plan
- 2025-08-12: Initial GIGAPLAN created. Captures current repo state and detailed backlog.
