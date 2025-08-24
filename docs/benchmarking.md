---
layout: default
title: "Benchmarking Guide"
---

# Benchmarking Guide

This guide covers how to run benchmarks, interpret results, and produce your own performance analysis of the BMSSP implementations.

## Quick Start

```bash
# Clone and setup
git clone https://github.com/openSVM/bmssp-benchmark-game.git
cd bmssp-benchmark-game
scripts/install_deps.sh --yes

# Quick benchmark (development)
python3 bench/runner.py --quick --out results-dev --timeout-seconds 20 --jobs 2

# Production benchmark  
python3 bench/runner.py --release --out results --timeout-seconds 600
```

## Benchmark Runner

The `bench/runner.py` script provides a unified interface for running benchmarks across all language implementations.

### Basic Usage

```bash
python3 bench/runner.py [options]
```

### Key Options

| Option | Description | Example |
|--------|-------------|---------|
| `--out DIR` | Output directory | `--out results-2024` |
| `--params FILE` | Parameter configuration | `--params bench/params_1000x.yaml` |
| `--release` | Use release/optimized builds | `--release` |
| `--quick` | Fast iteration (small graphs) | `--quick` |
| `--shared-inputs` | Generate graphs once, reuse | `--shared-inputs` |
| `--include-impls LIST` | Only test specific languages | `--include-impls rust,c,cpp` |
| `--exclude-impls LIST` | Skip specific languages | `--exclude-impls kotlin,elixir` |
| `--jobs N` | Parallel build jobs | `--jobs 4` |
| `--timeout-seconds N` | Per-implementation timeout | `--timeout-seconds 300` |

### Parameter Configuration

Benchmarks are configured via YAML files:

**Default parameters** (`bench/params.yaml`):
```yaml
graphs:
  - type: grid
    rows: 50
    cols: 50
    maxw: 100
  - type: er  
    n: 2500
    p: 0.002
    maxw: 100

k_values: [1, 4, 16]
B_values: [50, 200, 800]
seeds: [1, 2, 3, 4, 5]
trials: 5
```

**1000x parameters** (`bench/params_1000x.yaml`):
```yaml
graphs:
  - type: grid
    rows: 500
    cols: 500
    maxw: 1000
  - type: er
    n: 250000  
    p: 0.00002
    maxw: 1000

k_values: [1, 8, 64]
B_values: [500, 2000, 8000]
seeds: [1, 2, 3]
trials: 3
```

## Output Format

The runner generates several output files:

### Raw Data (`raw-{timestamp}.jsonl`)
```json
{"impl":"rust-bmssp","lang":"Rust","graph":"grid","n":2500,"m":9800,"k":4,"B":50,"seed":1,"time_ns":741251,"popped":868,"edges_scanned":3423,"heap_pushes":1047,"B_prime":50,"mem_bytes":241824}
{"impl":"c-bmssp","lang":"C","graph":"grid","n":2500,"m":9800,"k":4,"B":50,"seed":1,"time_ns":99065,"popped":1289,"edges_scanned":5119,"heap_pushes":1565,"B_prime":50,"mem_bytes":176800}
```

### Aggregated CSV (`agg-{timestamp}.csv`)
| impl | lang | graph | n | m | k | B | seed | threads | time_ns | popped | edges_scanned | heap_pushes | B_prime | mem_bytes |
|------|------|-------|---|---|---|---|------|---------|---------|--------|---------------|-------------|---------|-----------| 
| rust-bmssp | Rust | grid | 2500 | 9800 | 4 | 50 | 1 | 1 | 741251 | 868 | 3423 | 1047 | 50 | 241824 |

### Metadata (`meta-{timestamp}.yaml`)
```yaml
timestamp: "2024-01-15T10:30:00Z"
hostname: "github-actions-runner"
python_version: "3.11.2"
os_info: "Linux 5.15.0 x86_64"
implementations:
  rust: 
    version: "1.75.0"
    build_time: 45.2
  c:
    version: "gcc 11.3.0"  
    build_time: 2.1
parameters:
  total_configs: 45
  total_runs: 225
  timeout_seconds: 600
```

## Metrics Explained

### Performance Metrics

| Metric | Description | Units |
|--------|-------------|-------|
| `time_ns` | Wall-clock execution time | nanoseconds |
| `mem_bytes` | Peak memory usage | bytes |
| `popped` | Vertices removed from heap | count |
| `edges_scanned` | Edges examined during relaxation | count |
| `heap_pushes` | Priority queue insertions | count |

### Algorithm Metrics

| Metric | Description | Significance |
|--------|-------------|--------------|
| `B_prime` | Tight boundary distance | Next expansion threshold |
| `n`, `m` | Graph vertices, edges | Problem size |
| `k` | Number of sources | Multi-source complexity |
| `B` | Distance bound | Search radius |

### Derived Metrics

```python
# Efficiency ratios
edges_per_vertex = edges_scanned / popped
pushes_per_edge = heap_pushes / edges_scanned  
time_per_vertex = time_ns / popped

# Exploration fraction  
explored_fraction = popped / n

# Memory efficiency
bytes_per_vertex = mem_bytes / n
```

## Performance Analysis

### Language Comparison

To compare language performance:

```bash
# Run with identical inputs
python3 bench/runner.py --shared-inputs --include-impls rust,c,cpp,nim --out comparison

# Analyze results
python3 -c "
import pandas as pd
df = pd.read_csv('comparison/agg-*.csv')
grouped = df.groupby(['impl', 'lang'])['time_ns'].agg(['mean', 'std', 'min'])
print(grouped.sort_values('mean'))
"
```

### Scaling Analysis

To study algorithm scaling:

```bash
# Vary graph sizes
python3 bench/runner.py --params custom_scaling.yaml --include-impls rust --out scaling

# Create custom_scaling.yaml:
# graphs:
#   - {type: grid, rows: 10, cols: 10}
#   - {type: grid, rows: 50, cols: 50}  
#   - {type: grid, rows: 100, cols: 100}
#   - {type: grid, rows: 200, cols: 200}
```

### Memory Profiling

For detailed memory analysis:

```bash
# Linux: Use systemd-run for cgroup memory tracking
systemd-run --scope -p MemoryAccounting=yes python3 bench/runner.py --quick

# Per-process: Use time command
/usr/bin/time -v python3 bench/runner.py --quick --include-impls rust

# Heap profiling: Use valgrind for C/C++
valgrind --tool=massif ./impls/c/bin/bmssp_c --graph grid --rows 50 --cols 50 --k 4 --B 50
```

## Custom Benchmarks

### Graph Generation

```bash
# Generate custom graphs
python3 -c "
import bench.graph_gen as gg
g = gg.make_grid(100, 100, maxw=1000, seed=42)
gg.write_graph('custom.txt', g)
"

# Use custom graph
./impls/rust/target/release/bmssp --graph-file custom.txt --k 8 --B 500
```

### Parameter Sweeps

Create systematic parameter studies:

```yaml
# sweep_B.yaml - Study bound scaling
graphs:
  - type: grid
    rows: 100  
    cols: 100
    maxw: 100

k_values: [4]
B_values: [10, 20, 50, 100, 200, 500, 1000]
seeds: [1, 2, 3]
trials: 5
```

```yaml  
# sweep_k.yaml - Study multi-source scaling
graphs:
  - type: grid
    rows: 100
    cols: 100
    maxw: 100

k_values: [1, 2, 4, 8, 16, 32, 64]
B_values: [200]
seeds: [1, 2, 3] 
trials: 5
```

## Reproducibility

### Deterministic Results

All implementations use deterministic seeding:
- Graph generation uses `seed` parameter
- Random source selection uses `seed + trial_offset`  
- Results should be identical across runs

### Version Control

Track benchmark environments:
```bash
# Record exact versions
git rev-parse HEAD > results/git-commit.txt
rustc --version > results/rust-version.txt
gcc --version > results/gcc-version.txt

# Include in metadata
python3 bench/runner.py --out results 2>&1 | tee results/benchmark.log
```

### CI/CD Integration

GitHub Actions workflow (`.github/workflows/bench.yml`):
```yaml
name: Benchmark
on: [push, pull_request]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Install dependencies
      run: scripts/install_deps.sh --yes
    - name: Run benchmarks  
      run: python3 bench/runner.py --quick --out results-ci
    - name: Upload results
      uses: actions/upload-artifact@v3
      with:
        name: benchmark-results
        path: results-ci/
```

## Interpreting Results

### Performance Tiers

Based on typical 50×50 grid results:

- **🚀 Fastest (< 200μs):** Native compiled languages (C, C++, Rust)
- **⚡ Fast (200μs - 2ms):** Compiled high-level languages (Nim, Crystal)  
- **🐌 Slower (> 5ms):** VM-based languages (Kotlin, Elixir, Erlang)

### Algorithmic Insights

1. **Explored fraction:** `popped/n` correlates strongly with performance
2. **Edge efficiency:** `edges_scanned/popped` shows algorithm overhead
3. **Heap efficiency:** `heap_pushes/edges_scanned` indicates duplicate handling
4. **Memory scaling:** `mem_bytes/n` reveals implementation overhead

### Outlier Analysis

Common causes of performance outliers:
- **GC pauses** in managed languages
- **JIT warmup** in VM-based implementations  
- **System noise** (other processes, thermal throttling)
- **Input characteristics** (graph structure, source placement)

## Troubleshooting

### Build Issues

```bash
# Check dependencies
scripts/install_deps.sh --check-only

# Build individual implementations
cd impls/rust && cargo build --release
cd impls/c && make clean && make
cd impls/cpp && make clean && make  

# Debug build failures
python3 bench/runner.py --build-only --include-impls rust 2>&1 | tee build.log
```

### Runtime Issues

```bash
# Test individual implementations  
./impls/c/bin/bmssp_c --graph grid --rows 10 --cols 10 --k 2 --B 20 --trials 1 --json

# Validate output format
python3 -c "
import json
result = '{\"impl\":\"test\",...}'  # paste actual output
print(json.loads(result))
"

# Check memory limits
ulimit -v 1000000  # Limit virtual memory to 1GB
python3 bench/runner.py --quick
```

---

[← Implementations](implementations.html) | [Getting Started →](getting-started.html)