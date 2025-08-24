---
layout: default
title: "Getting Started"
---

# Getting Started with BMSSP Benchmark Game

This guide will walk you through setting up and running your first BMSSP benchmarks.

## Prerequisites

### Supported Platforms

- **Linux** (Ubuntu 20.04+, Debian 11+, CentOS 8+)
- **macOS** (10.15+)  
- **Windows** (Windows 10+ with WSL2 recommended)

### System Requirements

- **CPU:** x86_64 or ARM64
- **Memory:** 4GB+ recommended for larger benchmarks
- **Disk:** 2GB+ free space
- **Network:** Internet connection for dependency installation

## Quick Setup (Automated)

### Linux/macOS

```bash
# Clone repository
git clone https://github.com/openSVM/bmssp-benchmark-game.git
cd bmssp-benchmark-game

# Install all dependencies automatically
scripts/install_deps.sh --yes

# Verify installation
python3 bench/runner.py --build-only --include-impls rust,c
```

### Windows (PowerShell as Administrator)

```powershell
# Clone repository  
git clone https://github.com/openSVM/bmssp-benchmark-game.git
cd bmssp-benchmark-game

# Install dependencies
scripts/Install-Dependencies.ps1 -Yes

# Verify installation
python bench/runner.py --build-only --include-impls rust,c
```

## Manual Setup

If the automated setup fails, you can install dependencies manually:

### Core Dependencies

1. **Python 3.8+** with pip
   ```bash
   # Ubuntu/Debian
   sudo apt update && sudo apt install -y python3 python3-pip
   
   # macOS (with Homebrew)
   brew install python3
   
   # Install Python packages
   pip3 install --user pyyaml matplotlib jsonschema
   ```

2. **Rust** (for reference implementation)
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   source ~/.cargo/env
   ```

3. **C/C++ Toolchain**
   ```bash
   # Ubuntu/Debian
   sudo apt install -y build-essential
   
   # macOS  
   xcode-select --install
   
   # CentOS/RHEL
   sudo yum groupinstall -y "Development Tools"
   ```

### Optional Languages

Install additional language compilers as needed:

```bash
# Nim
curl https://nim-lang.org/choosenim/init.sh -sSf | sh

# Crystal  
# Ubuntu/Debian
curl -fsSL https://crystal-lang.org/install.sh | sudo bash

# Kotlin (requires Java)
sudo apt install -y openjdk-11-jdk
curl -s https://get.sdkman.io | bash
sdk install kotlin

# Elixir/Erlang
sudo apt install -y elixir erlang
```

## First Run

### Test Individual Implementation

Start with testing a single, fast implementation:

```bash
# Build and test Rust implementation
cd bmssp
cargo test
cargo build --release

# Run a quick test
./target/release/bmssp --graph grid --rows 10 --cols 10 --k 2 --B 20 --trials 1 --json
```

Expected output:
```json
{"impl":"rust-bmssp","lang":"Rust","graph":"grid","n":100,"m":360,"k":2,"B":20,"seed":1,"time_ns":12034,"popped":45,"edges_scanned":127,"heap_pushes":89,"B_prime":20,"mem_bytes":8192}
```

### Quick Multi-Language Benchmark

Run a fast benchmark across core implementations:

```bash
# Quick benchmark (small graphs, 2-3 minutes)
python3 bench/runner.py --quick --include-impls rust,c,cpp --out results-first --jobs 2

# Check results
ls results-first/
cat results-first/agg-*.csv
```

### Full Benchmark

Once comfortable with the system:

```bash
# Full benchmark (may take 10-30 minutes)
python3 bench/runner.py --release --out results-full --timeout-seconds 600

# Analyze results
python3 -c "
import pandas as pd
import glob
csv_files = glob.glob('results-full/agg-*.csv')
if csv_files:
    df = pd.read_csv(csv_files[0])
    print('Language performance summary:')
    summary = df.groupby('lang')['time_ns'].agg(['mean', 'std', 'count'])
    print(summary.sort_values('mean'))
"
```

## Understanding Output

### JSON Schema

Each implementation outputs JSON lines with these required fields:

| Field | Type | Description |
|-------|------|-------------|
| `impl` | string | Implementation identifier |
| `lang` | string | Programming language |
| `graph` | string | Graph type (grid/er/ba) |
| `n` | integer | Number of vertices |
| `m` | integer | Number of edges |  
| `k` | integer | Number of sources |
| `B` | integer | Distance bound |
| `seed` | integer | Random seed |
| `time_ns` | integer | Execution time (nanoseconds) |
| `popped` | integer | Vertices popped from heap |
| `edges_scanned` | integer | Edges examined |
| `heap_pushes` | integer | Priority queue insertions |
| `B_prime` | integer | Tight boundary found |
| `mem_bytes` | integer | Peak memory usage |

### Performance Interpretation

**Time scaling:** Expect roughly linear scaling with `popped` vertices and `edges_scanned`.

**Memory usage:** Should be dominated by graph storage (≈ 8-16 bytes per edge).

**Algorithm correctness:** For identical seeds, all implementations should report the same `popped`, `edges_scanned`, and `B_prime` values.

## Common Use Cases

### 1. Compare Language Performance

```bash
# Run identical workloads across languages
python3 bench/runner.py --shared-inputs --include-impls rust,c,cpp,nim,crystal --out lang-comparison

# Analyze relative performance
python3 -c "
import pandas as pd
df = pd.read_csv('lang-comparison/agg-*.csv')
baseline = df[df['lang'] == 'Rust']['time_ns'].mean()
for lang in df['lang'].unique():
    lang_time = df[df['lang'] == lang]['time_ns'].mean()
    print(f'{lang}: {lang_time/baseline:.2f}x vs Rust')
"
```

### 2. Algorithm Scaling Study

```bash
# Create scaling study parameters
cat > scaling_params.yaml << 'EOF'
graphs:
  - type: grid
    rows: 20
    cols: 20
  - type: grid  
    rows: 50
    cols: 50
  - type: grid
    rows: 100
    cols: 100

k_values: [4]
B_values: [50]
seeds: [1, 2, 3]
trials: 3
EOF

# Run scaling study
python3 bench/runner.py --params scaling_params.yaml --include-impls rust --out scaling-study
```

### 3. Bound Size Analysis

```bash
# Study how performance varies with bound B
cat > bound_study.yaml << 'EOF'
graphs:
  - type: grid
    rows: 50
    cols: 50

k_values: [4] 
B_values: [10, 25, 50, 100, 200, 500]
seeds: [1, 2, 3]
trials: 5
EOF

python3 bench/runner.py --params bound_study.yaml --include-impls rust,c --out bound-analysis
```

## Development Workflow

### Adding Custom Graph

```python
# Generate custom graph format
def write_custom_graph():
    with open('custom.txt', 'w') as f:
        f.write('4 5\n')  # 4 vertices, 5 edges
        f.write('0 1 10\n')  # edge (0,1) weight 10
        f.write('0 2 5\n')
        f.write('1 3 15\n') 
        f.write('2 3 8\n')
        f.write('1 2 3\n')

write_custom_graph()

# Test with custom graph
./bmssp/target/release/bmssp --graph-file custom.txt --k 1 --B 20 --seed 1 --trials 1 --json
```

### Performance Debugging

```bash
# Profile individual implementation
perf record -g ./impls/c/bin/bmssp_c --graph grid --rows 100 --cols 100 --k 8 --B 200
perf report

# Memory profiling
valgrind --tool=massif ./impls/c/bin/bmssp_c --graph grid --rows 50 --cols 50 --k 4 --B 50
massif-visualizer massif.out.*

# Time breakdown
time ./impls/cpp/bin/bmssp_cpp --graph grid --rows 100 --cols 100 --k 8 --B 200 --trials 10
```

## Troubleshooting

### Build Failures

**Rust compilation errors:**
```bash
# Update Rust toolchain
rustup update
rustc --version  # Should be 1.70+

# Clean rebuild
cd bmssp && cargo clean && cargo build --release
```

**C/C++ compilation errors:**
```bash
# Check compiler versions
gcc --version  # Should be 7.0+
g++ --version

# Debug build
cd impls/c && make clean && make DEBUG=1
```

### Runtime Issues

**JSON parsing errors:**
```bash
# Validate JSON output
./impls/rust/target/release/bmssp --graph grid --rows 5 --cols 5 --k 1 --B 10 --trials 1 --json | python3 -m json.tool
```

**Memory errors:**
```bash
# Check available memory
free -h

# Reduce problem size
python3 bench/runner.py --quick --params small_params.yaml
```

**Timeout issues:**
```bash
# Increase timeout
python3 bench/runner.py --timeout-seconds 1200 --out results

# Run single-threaded
python3 bench/runner.py --jobs 1 --out results
```

### Performance Issues

**Inconsistent results:**
```bash
# Check system load
top
iostat 1

# Run with fixed CPU affinity
taskset -c 0 python3 bench/runner.py --quick --include-impls rust

# Disable frequency scaling
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

## Next Steps

1. **Explore Algorithm Theory:** Read the [Algorithm](algorithm.html) page for mathematical details
2. **Study Implementations:** Check [Implementation Comparison](implementations.html) for language-specific insights  
3. **Advanced Benchmarking:** See [Benchmarking Guide](benchmarking.html) for production-grade analysis
4. **Contribute:** Check [CONTRIBUTING.md](https://github.com/openSVM/bmssp-benchmark-game/blob/main/CONTRIBUTING.md) to add new languages or features

## Resources

- **Repository:** [github.com/openSVM/bmssp-benchmark-game](https://github.com/openSVM/bmssp-benchmark-game)
- **Issues:** [Report bugs or request features](https://github.com/openSVM/bmssp-benchmark-game/issues)
- **Discussions:** [Join community discussions](https://github.com/openSVM/bmssp-benchmark-game/discussions)

---

[← Benchmarking](benchmarking.html) | [Home](index.html)