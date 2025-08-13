# bmssp benchmark game

Implementation of the algorithm in multiple languages to compare performance in a standard GitHub Actions environment.

Languages currently wired in this repo: Rust, C, C++, Nim, Crystal, Kotlin (JAR), Elixir (.exs), Erlang (.erl).

Rust implementation of **bounded multi-source shortest paths** (multi-source Dijkstra cut off at `B`).

## Run

```bash
cargo test
cargo bench -p bmssp
python3 bench/runner.py --release --out results

# fast iteration
python3 bench/runner.py --quick --out results-dev --timeout-seconds 20 --jobs 2
```

### One-time setup scripts

- Linux/macOS:
  - Run `scripts/install_deps.sh --yes` to auto-install Rust, Python deps, build tools, Crystal/shards, Nim.
  - Use `--check-only` to only report missing items.
- Windows:
  - Open PowerShell (as Administrator recommended) and run `scripts/Install-Dependencies.ps1 -Yes`.
  - Add `-CheckOnly` to only report.

## Complexity

Let `U = { v | d(v) < B }` and `E(U)` be edges scanned from `U`.

- Time: `O((|E(U)| + |U|) log |U|)` with binary heap; worst-case `O((m+n) log n)`.
- Space: `Θ(n + m)` graph + `Θ(n)` distances/flags + heap bounded by frontier size.

Use `Graph::memory_estimate_bytes()` to get a byte estimate at runtime.


Here’s the no-BS, self-contained write-up you asked for. It includes the theory, proofs at the right granularity, complexity, comparisons against the usual suspects, and **charts** (model-based, not empirical—use them to reason about trends, not absolutes).

---

# Bounded Multi-Source Shortest Paths (BMSSP)

## What problem it solves

Given a directed graph $G=(V,E)$ with non-negative weights $w:E\to \mathbb{R}_{\ge 0}$, a **set of sources** $S\subseteq V$ with initial offsets $d_0(s)$ (usually 0), and a **distance bound** $B$, compute:

* For every vertex $v$ with true shortest-path distance $d(v) < B$, the exact distance $d(v)$.
* The **explored set** $U=\{v\in V\mid d(v)<B\}$.
* The **tight boundary** $B' = \min\{ \hat d(x)\mid x \notin U\}$, i.e., the smallest tentative label never popped (next frontier).

This is **Dijkstra from multiple sources that halts when the next tentative key would be $\ge B$**.

---

## Algorithm (binary-heap version)

Same invariant as Dijkstra: a node is popped exactly once with its final shortest distance. The only change is the early-exit cut.

**Initialize**

* $\forall v\in V:\ \text{dist}[v] \leftarrow +\infty$
* For each source $s\in S$: if $d_0(s) < B$ set $\text{dist}[s]\leftarrow d_0(s)$ and push $(d_0(s),s)$ into a min-PQ.
* $B' \leftarrow B$

**Main loop**

* Pop $(d,u)$. If $d \ne \text{dist}[u]$ continue (stale).
* If $d \ge B$, set $B'\gets d$ and **stop**.
* For each edge $(u,v,w)$:
  $\text{nd}=d+w$.

  * If $\text{nd} < \text{dist}[v]$ and $\text{nd} < B$: relax and push.
  * Else if $\text{nd} \ge B$: update $B' \leftarrow \min(B', \text{nd})$ (tracks the smallest over-bound key observed).

Return $(U, B')$ where $U$ are the popped vertices.

> Multi-source is trivial: seed multiple entries. All standard Dijkstra proofs still apply.

---

## Correctness (sketch you can actually use)

**Invariant** (Dijkstra): When a node $u$ is popped, $\text{dist}[u]=d(u)$.
Proof carries over because (1) weights $\ge 0$, (2) heap order guarantees we never pop a label larger than any alternate path to that node, (3) early exit only **reduces** the set of popped nodes; it never allows popping out of order.

**Boundary lemma.** Let $U$ be nodes popped before exit. Then
$B' = \min\{\hat d(x)\mid x\in V\setminus U\}$ — the smallest tentative distance still in the heap (or discovered and $\ge B$).
So $B' \ge B$ and is the next tight phase boundary if you continue search.

---

## Complexity

Let $U=\{v\mid d(v)<B\}$ and $E(U)=\{(u,v)\in E\mid u\in U\}$.

* **Time (binary heap):**

  $$
  T = \mathcal{O}\big((|E(U)| + |U|)\log |U|\big)
  $$

  In the worst case ($B$ large), $|U|=n$, $|E(U)|=m$ → standard $\mathcal{O}((m+n)\log n)$.

* **Space:** Graph storage $\Theta(n+m)$ + working arrays $\Theta(n)$ + heap up to $\Theta(|U|)$.
  Asymptotically $\Theta(n+m)$.

* **Multi-source impact:** Doesn’t change big-O. Practically lowers the radius needed to reach a given $f = |U|/n$; you explore **more shallow balls from more centers** instead of a deep ball from one center.

---

## Where BMSSP wins / loses

**Wins**

* You only care about a **radius** (range search, k-hop neighborhoods, geo/proximity queries, limited-distance labeling).
* **Repeated queries** that increase $B$ gradually; reuse $B'$ to chunk work in phases.
* Graphs where $f=|U|/n \ll 1$ for your typical $B$. Cost drops roughly like $f \log (fn)$.

**Loses**

* $B$ approaches graph diameter ⇒ you’re doing full SSSP; there’s no magic: you pay Dijkstra.
* Integer weights with **small range**: specialized queues (Dial/radix) beat binary heaps.
* Heavy parallel iron: **Δ-stepping** or GPU SSSP can dominate on large, sparse graphs with good partitioning.

---

## Comparison with existing SSSP families

| Method                         | Weights                  |                          Time (typical) |             Memory | Pros                                 | Cons                                                             |       |   |    |               |                                                   |                               |
| ------------------------------ | ------------------------ | --------------------------------------: | -----------------: | ------------------------------------ | ---------------------------------------------------------------- | ----- | - | -- | ------------- | ------------------------------------------------- | ----------------------------- |
| **BMSSP (this)** + binary heap | non-negative             | $\mathcal{O}((m+n)\log n)$ | $\Theta(n+m)$ | Exact within bound; simple; great when $f \ll 1$. | If $f\to1$, same as Dijkstra. |
| Dijkstra (binary heap)         | non-negative             |              $\mathcal{O}((m+n)\log n)$ |      $\Theta(n+m)$ | Baseline, robust.                    | Slower on integer weights; no early stop unless you add a bound. |       |   |    |               |                                                   |                               |
| Dijkstra (Fibonacci)           | non-negative             |     $\mathcal{O}(m + n\log n)$ (theory) |      big constants | Better asymptotics.                  | Not worth it in practice.                                        |       |   |    |               |                                                   |                               |
| **Dial / bucket queues**       | integer weights $0..C$   |                   $\mathcal{O}(m + nC)$ |    $\Theta(n+m+C)$ | Blazing if $C$ small; predictable.   | Explodes with large $C$ or big $B$ (buckets).                    |       |   |    |               |                                                   |                               |
| Radix / 0-1 BFS                | small integer            |                             near-linear |      $\Theta(n+m)$ | Ideal for tiny ranges (0-1 BFS).     | Narrow use-case.                                                 |       |   |    |               |                                                   |                               |
| Δ-stepping (parallel)          | non-negative             | $\approx$ near-linear per level on PRAM | buckets + frontier | Parallel-friendly; fast in practice. | Needs tuning (δ); irregular work.                                |       |   |    |               |                                                   |                               |
| Bellman-Ford                   | any                      |                       $\mathcal{O}(nm)$ |        $\Theta(n)$ | Negative edges (no cycles).          | Too slow; not comparable for your case.                          |       |   |    |               |                                                   |                               |
| A\*                            | non-negative + heuristic |  like Dijkstra on set actually explored |      like Dijkstra | If heuristic is good, dominates.     | Needs problem-specific heuristics.                               |       |   |    |               |                                                   |                               |

**Bottom line:** If you need exact distances **up to a bound** and you’re not on tiny integer weights, BMSSP (bounded Dijkstra) is the simplest, most dependable hammer. If weights are small integers, buckets win. If you’re on many-core/GPU, consider Δ-stepping or GPU SSSP.

---

## Charts (model-based trends)

These plots use simple cost models (they **are not** runtime measurements). They illustrate how the math scales with explored fraction $f$, bound $B$, and weight range. Use your own `cargo bench` to pin real numbers.

1. **Relative time vs explored fraction**
   Bounded Dijkstra cost shrinks roughly like $f \log (fn)$ vs full Dijkstra at $f=1$.

![Relative time vs fraction](sandbox:/mnt/data/bmssp_rel_time_vs_fraction.png)

2. **Bounded Dijkstra vs Dial (integer weights)**
   When the weight range $C$ is small, Dial can beat binary heaps; as $B$ grows or $C$ is large, buckets become a tax.

![Relative time vs bound](sandbox:/mnt/data/bmssp_rel_time_vs_bound.png)

3. **Extra memory (excluding adjacency)**
   All Dijkstra variants pay $O(n)$. Bucketed queues add $O(B)$ (or $O(C)$) worth of buckets.

![Memory overhead](sandbox:/mnt/data/bmssp_memory_overhead.png)

> Want empirical plots? Run the provided Rust bench across varying $B$, $k=|S|$, $n,m$, and (optionally) a bucketed queue variant. I can script `cargo bench` + CSV + gnuplot for you.

### Crystal implementation

Crystal port lives in `impls/crystal` and follows the same CLI and JSON contract.

Build locally (if Crystal is installed):

```bash
cd impls/crystal
shards build --release
./bin/bmssp_cr --graph grid --rows 20 --cols 20 --k 8 --B 50 --seed 1 --trials 2 --json
```

The bench runner will auto-detect Crystal (`crystal` + `shards` in PATH) and include its results.

---

## Implementation notes that actually matter

* Keep `dist` as `u64`. Use `saturating_add` to avoid overflow during relaxations.
* Don’t attempt “decrease-key”; just push duplicates and skip stale pops. It’s faster with Rust’s `BinaryHeap`.
* Track `B'` while relaxing edges that would cross the bound—this is your next-phase threshold.
* Multi-source is just seeding many `(node, offset)` entries. If you repeat with larger $B$, reuse `dist` as a warm-start and continue; it preserves optimality because labels are monotone.
* Memory: adjacency dominates. The rest is a few `Vec`s of size $n$ and the heap/frontier.

---

## Complexity re-stated (so you don’t scroll back)

* **Time:** $\boxed{ \mathcal{O}\big((|E(U)|+|U|)\log |U|\big) }$
  Worst case: $\mathcal{O}((m+n)\log n)$.

* **Space:** $\boxed{ \Theta(n+m) }$ total; working state $\Theta(n)$ + heap $O(|U|)$.

If you want byte-accurate numbers, the Rust crate includes a `memory_estimate_bytes()` helper; for real allocations, measure with `heaptrack`/`massif` or Linux cgroups.

---

## When to prefer other queues

* **Small integer weights** (e.g., 0–255): Dial/radix will beat binary heaps. BMSSP still applies—just stop at $B$—but use buckets.
* **Parallel hardware**: Δ-stepping buckets **plus** bound $B$ works well; you get level-synchronous waves clipped at $B$.
* **Heuristic-rich domains**: A\* with an admissible heuristic can explore **far less than $U$** for the same $B$.

---

## How to produce *real* comparison charts (bench recipe)

* Use the Rust crate I gave you (`cargo bench -p bmssp`) and vary:

  * $n,m$ (grid, ER random, power-law)
  * number of sources $k$
  * bound $B$
* Implement a second queue:

  * Dial (if your weights are bounded ints)
  * or a bucketed Δ-stepping variant (single-thread first)
* Capture: push counts, relax counts, popped vertices, wall-clock (release), and peak RSS.
* Plot **time vs |U|**, **time vs B**, **pushes per edge**; the trends will match the charts above, with real constants.

---

## TL;DR

* If $B$ is small relative to typical distances, **BMSSP saves you real work**, exactly as the $f\log(fn)$ model predicts.
* If weights are tiny integers, **use buckets** (Dial) and still bound by $B$.
* Otherwise, bounded Dijkstra with a binary heap is the **clean default**—simple, exact, and fast enough.

If you want this rewritten around the **recursive/pivoted BMSSP** from your screenshot (the one with `FindPivots`, batching, etc.), send the full section of the paper and I’ll extend the Rust crate to that variant and give you *measured* charts next.
