---
layout: default
title: "BMSSP Benchmark Game"
---

# Bounded Multi-Source Shortest Paths (BMSSP) Benchmark Game

Welcome to the **BMSSP Benchmark Game** - a comprehensive implementation and benchmarking suite for the Bounded Multi-Source Shortest Paths algorithm across multiple programming languages.

## Overview

This project provides:
- **Multi-language implementations** of the BMSSP algorithm in 8 languages: Rust, C, C++, Nim, Crystal, Kotlin, Elixir, and Erlang
- **Comprehensive benchmarking framework** with standardized CLI interfaces
- **Theoretical analysis** with complexity proofs and algorithm comparisons
- **Empirical performance data** from GitHub Actions environment

## What is BMSSP?

**Bounded Multi-Source Shortest Paths (BMSSP)** is a variant of Dijkstra's algorithm that:
- Starts from **multiple source vertices** simultaneously
- **Halts exploration** when the next vertex distance would exceed a bound `B`
- Provides **exact shortest paths** for all vertices within the distance bound
- Achieves **significant performance gains** when the explored fraction is small

## Quick Start

```bash
# Clone the repository
git clone https://github.com/openSVM/bmssp-benchmark-game.git
cd bmssp-benchmark-game

# Install dependencies (Linux/macOS)
scripts/install_deps.sh --yes

# Run quick benchmark
python3 bench/runner.py --quick --out results-dev --timeout-seconds 20 --jobs 2

# Run comprehensive tests
cargo test
cargo bench -p bmssp
```

## Language Implementations

| Language | Implementation | Build System | Performance Tier |
|----------|----------------|--------------|------------------|
| **C** | `impls/c/` | Makefile | 🚀 Fastest |
| **C++** | `impls/cpp/` | Makefile | 🚀 Fastest |
| **Rust** | `bmssp/` | Cargo | 🚀 Fastest |
| **Nim** | `impls/nim/` | Nim compiler | ⚡ Fast |
| **Crystal** | `impls/crystal/` | Shards | ⚡ Fast |
| **Kotlin** | `impls/kotlin/` | Gradle → JAR | 🐌 Slower |
| **Elixir** | `impls/elixir/` | Mix | 🐌 Slower |
| **Erlang** | `impls/erlang/` | Erlang compiler | 🐌 Slower |

## Latest Benchmark Results

Here's a snapshot from our standardized benchmark on a 50×50 grid graph with 4 sources and bound B=50:

| Implementation | Language | Time (ns) | Memory (bytes) | Vertices Popped | Edges Scanned |
|----------------|----------|-----------|----------------|-----------------|---------------|
| c-bmssp | C | 99,065 | 176,800 | 1,289 | 5,119 |
| cpp-bmssp | C++ | 117,480 | 176,800 | 1,064 | 4,224 |
| rust-bmssp | Rust | 741,251 | 241,824 | 868 | 3,423 |
| erlang-bmssp | Erlang | 1,155,739 | 196,800 | 691 | 2,701 |
| kotlin-bmssp | Kotlin | 5,308,820 | 196,800 | 1,102 | 4,386 |
| elixir-bmssp | Elixir | 5,410,039 | 196,800 | 870 | 3,447 |

*Results from GitHub Actions standard environment*

## Key Features

### 🧮 Algorithm Theory
- Complete mathematical analysis with complexity proofs
- Comparison with standard SSSP algorithms (Dijkstra, A*, Δ-stepping)
- Model-based performance charts and trends

### 🛠 Implementation Standards
- Unified CLI interface across all languages
- JSON output format for easy analysis
- Standardized graph generators (grid, Erdős–Rényi, Barabási–Albert)
- Memory usage tracking and optimization notes

### 📊 Benchmarking Framework
- Automated build and test pipeline
- Cross-language performance comparison
- Configurable graph parameters and test scenarios
- Statistical analysis and report generation

### 🔬 Verification
- Correctness validation across implementations
- Deterministic seeding for reproducible results
- Invariant checking and parity testing

## Navigation

- **[Algorithm Details](algorithm.html)** - Deep dive into BMSSP theory, proofs, and complexity analysis
- **[Implementation Guide](implementations.html)** - Language-specific details and performance characteristics  
- **[Benchmarking](benchmarking.html)** - How to run benchmarks and interpret results
- **[Getting Started](getting-started.html)** - Setup instructions and first steps

## Contributing

We welcome contributions! See our [Contributing Guide](https://github.com/openSVM/bmssp-benchmark-game/blob/main/CONTRIBUTING.md) for:
- Adding new language implementations
- Improving existing code
- Extending the benchmarking framework
- Documentation improvements

## License

This project is dual-licensed under MIT and Apache 2.0 licenses. See [LICENSE-MIT](https://github.com/openSVM/bmssp-benchmark-game/blob/main/LICENSE-MIT) and [LICENSE-APACHE](https://github.com/openSVM/bmssp-benchmark-game/blob/main/LICENSE-APACHE) for details.