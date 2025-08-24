---
layout: default
title: "Algorithm Theory and Analysis"
---

# Bounded Multi-Source Shortest Paths: Algorithm Theory

## Problem Definition

Given a directed graph $G=(V,E)$ with non-negative weights $w:E\to \mathbb{R}_{\ge 0}$, a **set of sources** $S\subseteq V$ with initial offsets $d_0(s)$ (usually 0), and a **distance bound** $B$, compute:

- For every vertex $v$ with true shortest-path distance $d(v) < B$, the exact distance $d(v)$
- The **explored set** $U=\{v\in V\mid d(v)<B\}$
- The **tight boundary** $B' = \min\{ \hat d(x)\mid x \notin U\}$, i.e., the smallest tentative label never popped (next frontier)

This is **Dijkstra from multiple sources that halts when the next tentative key would be $\ge B$**.

## Algorithm (Binary Heap Version)

The algorithm maintains the same invariant as Dijkstra: a node is popped exactly once with its final shortest distance. The only change is the early-exit condition.

### Initialization

```
For all v ∈ V: dist[v] ← +∞
For each source s ∈ S:
    if d₀(s) < B:
        dist[s] ← d₀(s)
        push (d₀(s), s) into min-priority-queue
B' ← B
```

### Main Loop

```
while priority_queue is not empty:
    (d, u) ← pop_min()
    
    if d ≠ dist[u]:
        continue  // Skip stale entry
    
    if d ≥ B:
        B' ← d
        break     // Early termination
    
    mark u as processed
    
    for each edge (u, v, w):
        nd ← d + w
        
        if nd < dist[v] and nd < B:
            dist[v] ← nd
            push (nd, v) into priority_queue
        elif nd ≥ B:
            B' ← min(B', nd)  // Track boundary
```

**Return:** $(U, B')$ where $U$ are the processed vertices.

> **Multi-source insight:** Seeding multiple entries is trivial. All standard Dijkstra proofs still apply.

## Correctness Proof

### Invariant Preservation

**Dijkstra Invariant:** When a node $u$ is popped, $\text{dist}[u] = d(u)$ (true shortest distance).

**Proof sketch:** The proof carries over from standard Dijkstra because:
1. Weights are non-negative
2. Heap order guarantees we never pop a label larger than any alternate path to that node  
3. Early exit only **reduces** the set of popped nodes; it never allows popping out of order

### Boundary Correctness

**Boundary Lemma:** Let $U$ be nodes popped before exit. Then:
$$B' = \min\{\hat d(x)\mid x\in V\setminus U\}$$

This is the smallest tentative distance still in the heap (or discovered and $\ge B$).

**Properties:**
- $B' \ge B$ (by construction)
- $B'$ is the next tight phase boundary if you continue the search
- All vertices in $U$ have exact shortest distances
- All vertices with $d(v) < B$ are in $U$

## Complexity Analysis

Let $U=\{v\mid d(v)<B\}$ and $E(U)=\{(u,v)\in E\mid u\in U\}$.

### Time Complexity

$$\boxed{T = \mathcal{O}\big((|E(U)| + |U|)\log |U|\big)}$$

**Breakdown:**
- Each vertex in $U$ is popped exactly once: $\mathcal{O}(|U| \log |U|)$
- Each edge from $U$ is relaxed at most once: $\mathcal{O}(|E(U)| \log |U|)$
- Heap operations: $\mathcal{O}(\log |U|)$ per operation

**Worst case:** When $B$ is large, $|U|=n$ and $|E(U)|=m$, giving standard $\mathcal{O}((m+n)\log n)$.

**Best case:** When $B$ is small, $|U| \ll n$, achieving significant speedup.

### Space Complexity

$$\boxed{S = \Theta(n+m)}$$

**Components:**
- Graph storage: $\Theta(n+m)$ 
- Distance array: $\Theta(n)$
- Priority queue: $\mathcal{O}(|U|)$ at peak
- Working flags: $\Theta(n)$

Asymptotically dominated by graph storage.

### Multi-Source Impact

**Time:** No change to big-O complexity. Practically lowers the radius needed to reach a given explored fraction $f = |U|/n$.

**Intuition:** You explore **shallow balls from multiple centers** instead of a deep ball from one center.

## Performance Analysis

### Explored Fraction Model

Define $f = |U|/n$ as the fraction of vertices explored.

**Relative speedup** compared to full Dijkstra:
$$\text{Speedup} \approx \frac{1}{f \log(fn) + \epsilon}$$

where $\epsilon$ accounts for overhead.

**Key insight:** When $f \ll 1$, BMSSP provides substantial speedup exactly as predicted by the model.

### When BMSSP Wins

✅ **Small distance bounds** relative to graph diameter  
✅ **Range queries** and proximity search  
✅ **Iterative algorithms** that gradually increase $B$  
✅ **Sparse exploration** where $f = |U|/n \ll 1$  

### When BMSSP Loses

❌ **Large bounds** approaching graph diameter ($f \to 1$)  
❌ **Small integer weights** (specialized queues like Dial are better)  
❌ **Highly parallel scenarios** (Δ-stepping might dominate)  

## Comparison with Alternative Algorithms

| Algorithm | Weight Type | Time Complexity | Space | Best Use Case |
|-----------|-------------|-----------------|-------|---------------|
| **BMSSP (Binary Heap)** | Non-negative | $\mathcal{O}((m+n)\log n)$ | $\Theta(n+m)$ | Bounded search, $f \ll 1$ |
| Dijkstra (Binary Heap) | Non-negative | $\mathcal{O}((m+n)\log n)$ | $\Theta(n+m)$ | General-purpose baseline |
| Dijkstra (Fibonacci) | Non-negative | $\mathcal{O}(m + n\log n)$ | High constants | Theoretical interest |
| **Dial/Bucket Queue** | Integer $[0,C]$ | $\mathcal{O}(m + nC)$ | $\Theta(n+m+C)$ | Small integer weights |
| **Δ-stepping** | Non-negative | Near-linear per level | Buckets + frontier | Parallel processing |
| A* | Non-negative + heuristic | Like Dijkstra on explored set | Like Dijkstra | Problem-specific heuristics |
| Bellman-Ford | Any (with negative) | $\mathcal{O}(nm)$ | $\Theta(n)$ | Negative edge weights |

### Recommendation

- **Default choice:** BMSSP with binary heap for exact bounded shortest paths
- **Integer weights + small range:** Use Dial queue with bound $B$  
- **Parallel hardware:** Consider Δ-stepping with bound $B$
- **Heuristic available:** A* can explore less than $|U|$ for same bound

## Implementation Notes

### Critical Optimizations

1. **Skip decrease-key:** Push duplicates and ignore stale pops (faster with most heap implementations)
2. **Overflow protection:** Use saturating arithmetic for distance calculations
3. **Boundary tracking:** Update $B'$ during edge relaxation to get next phase threshold
4. **Multi-source seeding:** Simply initialize multiple heap entries
5. **Memory layout:** Keep distance array cache-friendly

### Warm Restart

For iterative algorithms that increase $B$:
```rust
// Reuse previous distances as warm start
// dist array preserves optimality due to monotonicity
let (new_explored, new_boundary) = bmssp_continue(graph, dist, prev_boundary, new_bound);
```

This preserves optimality because shortest path distances are monotone with respect to the bound.

## Mathematical Properties

### Monotonicity
If $B_1 \leq B_2$, then $U_1 \subseteq U_2$ and $B'_1 \geq B'_2$.

### Optimality  
All distances in $U$ are exact shortest path distances from the nearest source.

### Completeness
Every vertex $v$ with $d(v) < B$ is included in $U$.

### Boundary Tightness
$B'$ is the minimum distance among all vertices not in $U$, providing the exact threshold for the next expansion phase.

---

[← Back to Home](index.html) | [Implementations →](implementations.html)