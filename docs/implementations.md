---
layout: default
title: "Implementation Comparison"
---

# Language Implementations

This page provides detailed information about each language implementation of the BMSSP algorithm, including performance characteristics, build instructions, and implementation notes.

## Overview

All implementations follow the same standardized interface:

### CLI Contract
```bash
./bmssp --graph <type> --rows <r> --cols <c> --k <sources> --B <bound> --seed <s> --trials <n> --json
```

### JSON Output Format
```json
{
  "impl": "rust-bmssp",
  "lang": "Rust", 
  "graph": "grid",
  "n": 2500,
  "m": 9800,
  "k": 4,
  "B": 50,
  "seed": 1,
  "time_ns": 741251,
  "popped": 868,
  "edges_scanned": 3423,
  "heap_pushes": 1047,
  "B_prime": 50,
  "mem_bytes": 241824
}
```

## Performance Tiers

Based on empirical benchmarks in GitHub Actions environment:

🚀 **Fastest (< 200μs):** C, C++, Rust  
⚡ **Fast (200μs - 2ms):** Nim, Crystal  
🐌 **Slower (> 5ms):** Kotlin, Elixir, Erlang

## Language Details

### 🚀 C Implementation

**Location:** `impls/c/`  
**Build:** `make`  
**Binary:** `bin/bmssp_c`

```bash
cd impls/c
make
./bin/bmssp_c --graph grid --rows 50 --cols 50 --k 4 --B 50 --seed 1 --trials 5 --json
```

**Performance:** ⭐⭐⭐⭐⭐ Fastest overall  
**Typical time:** ~99μs for 50×50 grid, k=4, B=50

**Implementation highlights:**
- Manual memory management with careful allocation
- Efficient binary heap using arrays
- Saturating arithmetic for overflow protection
- Cache-friendly memory layout

**Code structure:**
```c
typedef struct {
    uint32_t node;
    uint64_t dist;
} HeapEntry;

typedef struct {
    HeapEntry* data;
    size_t size, capacity;
} BinaryHeap;
```

### 🚀 C++ Implementation  

**Location:** `impls/cpp/`  
**Build:** `make`  
**Binary:** `bin/bmssp_cpp`

**Performance:** ⭐⭐⭐⭐⭐ Near C performance  
**Typical time:** ~117μs for 50×50 grid, k=4, B=50

**Implementation highlights:**
- STL `priority_queue` with custom comparator
- RAII for automatic memory management  
- Template-based graph representation
- Modern C++17 features

**Code structure:**
```cpp
using PQEntry = std::pair<uint64_t, uint32_t>;
std::priority_queue<PQEntry, std::vector<PQEntry>, std::greater<PQEntry>> pq;
```

### 🚀 Rust Implementation

**Location:** `bmssp/` (Cargo crate)  
**Build:** `cargo build --release`  
**Binary:** `target/release/bmssp`

**Performance:** ⭐⭐⭐⭐ Excellent  
**Typical time:** ~741μs for 50×50 grid, k=4, B=50

**Implementation highlights:**
- Memory safety without garbage collection
- `BinaryHeap` from standard library
- Zero-cost abstractions
- Extensive test suite and benchmarks

**Code structure:**
```rust
use std::collections::BinaryHeap;

#[derive(Copy, Clone, Eq, PartialEq)]
struct State {
    cost: u64,
    position: usize,
}

impl Ord for State {
    fn cmp(&self, other: &Self) -> Ordering {
        other.cost.cmp(&self.cost)  // Min-heap
    }
}
```

**Cargo features:**
```bash
cargo test                    # Run test suite
cargo bench -p bmssp         # Benchmark suite  
cargo doc --open             # Generate docs
```

### ⚡ Nim Implementation

**Location:** `impls/nim/`  
**Build:** `nim c -d:release src/bmssp.nim`  
**Binary:** `src/bmssp`

**Performance:** ⭐⭐⭐⭐ Fast  
**Typical time:** ~2ms for 50×50 grid, k=4, B=50

**Implementation highlights:**
- Compiled to efficient C code
- Manual memory management with garbage collection
- Nim's `heapqueue` module
- Python-like syntax with C performance

### ⚡ Crystal Implementation

**Location:** `impls/crystal/`  
**Build:** `shards build --release`  
**Binary:** `bin/bmssp_cr`

**Performance:** ⭐⭐⭐⭐ Fast  
**Typical time:** ~2ms for 50×50 grid, k=4, B=50

**Implementation highlights:**
- Ruby-like syntax, compiled to efficient native code
- Built-in priority queue implementation
- Static type checking with type inference
- Automatic memory management

**Build and run:**
```bash
cd impls/crystal
shards build --release
./bin/bmssp_cr --graph grid --rows 20 --cols 20 --k 8 --B 50 --seed 1 --trials 2 --json
```

### 🐌 Kotlin Implementation

**Location:** `impls/kotlin/`  
**Build:** `gradle shadowJar`  
**Binary:** `build/libs/bmssp-all.jar`

**Performance:** ⭐⭐ Slower (JVM overhead)  
**Typical time:** ~5.3ms for 50×50 grid, k=4, B=50

**Implementation highlights:**
- JVM-based with startup overhead
- Java interoperability  
- Functional programming features
- Type-safe null handling

**Run:**
```bash
cd impls/kotlin
gradle shadowJar
java -jar build/libs/bmssp-all.jar --graph grid --rows 50 --cols 50 --k 4 --B 50
```

### 🐌 Elixir Implementation

**Location:** `impls/elixir/`  
**Build:** No build step (interpreted)  
**Script:** `bmssp.exs`

**Performance:** ⭐⭐ Slower (BEAM VM)  
**Typical time:** ~5.4ms for 50×50 grid, k=4, B=50

**Implementation highlights:**
- Functional programming paradigm
- BEAM VM with actor model
- Pattern matching and immutable data
- Fault-tolerant design

**Run:**
```bash
cd impls/elixir  
elixir bmssp.exs --graph grid --rows 50 --cols 50 --k 4 --B 50
```

### 🐌 Erlang Implementation

**Location:** `impls/erlang/`  
**Build:** `erlc bmssp.erl`  
**Binary:** `bmssp.beam`

**Performance:** ⭐⭐⭐ Moderate (BEAM VM)  
**Typical time:** ~1.2ms for 50×50 grid, k=4, B=50

**Implementation highlights:**
- Concurrent functional programming
- BEAM VM with hot code reloading
- Built for distributed systems
- Pattern matching and message passing

## Implementation Standards

### Graph Generation

All implementations support three graph types:

1. **Grid graphs:** `--graph grid --rows R --cols C`
   - Regular 2D lattice with 4-connectivity
   - Predictable structure for testing

2. **Erdős–Rényi random:** `--graph er --n N --p P`  
   - Each edge exists with probability P
   - Good for average-case analysis

3. **Barabási–Albert:** `--graph ba --n N --m0 M0 --m M`
   - Preferential attachment model
   - Power-law degree distribution

### Shared Graph Input

For deterministic comparison across languages:
```bash
python3 bench/runner.py --shared-inputs --include-impls rust,c,cpp
```

This generates graphs once and reuses them, ensuring identical inputs.

### Memory Tracking

Each implementation reports peak memory usage:
- **Graph storage:** Adjacency lists ($\Theta(n+m)$)  
- **Working arrays:** Distance, visited flags ($\Theta(n)$)
- **Priority queue:** Up to $O(|U|)$ entries
- **Implementation overhead:** Language-specific

### Verification

All implementations must:
1. **Produce identical results** for same seed and parameters
2. **Match reference metrics:** `popped`, `edges_scanned`, `B_prime`  
3. **Pass correctness tests** on small graphs
4. **Handle edge cases:** Empty graphs, single vertex, no sources

## Build and Test All

```bash
# Install dependencies
scripts/install_deps.sh --yes

# Build all implementations  
python3 bench/runner.py --build-only

# Quick test (subset of languages)
python3 bench/runner.py --quick --include-impls rust,c,cpp --out results-test

# Full benchmark suite
python3 bench/runner.py --release --out results --timeout-seconds 600
```

## Adding New Languages

See [CONTRIBUTING.md](https://github.com/openSVM/bmssp-benchmark-game/blob/main/CONTRIBUTING.md) for detailed instructions on adding new language implementations.

**Requirements:**
1. Implement the standard CLI interface
2. Output JSON format with required fields
3. Use push-duplicates, skip-stale approach
4. Track and report all metrics correctly
5. Add build/run hooks to `bench/runner.py`

**Verification checklist:**
- [ ] Identical results vs Rust reference implementation
- [ ] Correct handling of all graph types  
- [ ] Proper memory usage reporting
- [ ] JSON schema compliance
- [ ] Build integration working

---

[← Algorithm Theory](algorithm.html) | [Benchmarking →](benchmarking.html)