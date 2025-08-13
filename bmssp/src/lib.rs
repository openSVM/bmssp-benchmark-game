//! bmssp: bounded multi-source shortest paths.
//! Multi-source Dijkstra that halts when the next tentative distance >= bound B.
//! Returns distances for nodes with d < B, explored set U, and tight boundary B'.
use std::cmp::{Ordering, Reverse};
use std::collections::BinaryHeap;

pub type Node = usize;
pub type Weight = u64;

#[derive(Clone, Debug)]
pub struct Graph {
    pub adj: Vec<Vec<(Node, Weight)>>,
}
impl Graph {
    pub fn new(n: usize) -> Self { Self { adj: vec![Vec::new(); n] } }
    pub fn len(&self) -> usize { self.adj.len() }
    pub fn add_edge(&mut self, u: Node, v: Node, w: Weight) { self.adj[u].push((v,w)); }
    pub fn add_undirected_edge(&mut self, u: Node, v: Node, w: Weight) {
        self.add_edge(u,v,w); self.add_edge(v,u,w);
    }
    pub fn memory_estimate_bytes(&self) -> usize {
        let n = self.adj.len();
        let m = self.adj.iter().map(|v| v.len()).sum::<usize>();
        let edge_bytes = m * (std::mem::size_of::<usize>() + std::mem::size_of::<u64>());
        let vec_headers = n * 3 * std::mem::size_of::<usize>();
        let outer_vec_header = 3 * std::mem::size_of::<usize>();
        let dist_bytes = n * std::mem::size_of::<u64>();
        let flags_bytes = n * std::mem::size_of::<u8>() * 2;
        edge_bytes + vec_headers + outer_vec_header + dist_bytes + flags_bytes
    }
}

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
struct Entry { d: Weight, v: Node }
impl Ord for Entry {
    fn cmp(&self, other: &Self) -> Ordering {
        self.d.cmp(&other.d).then(self.v.cmp(&other.v))
    }
}
impl PartialOrd for Entry {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> { Some(self.cmp(other)) }
}

#[derive(Debug, Clone)]
pub struct BmsspResult {
    pub dist: Vec<Weight>,
    pub explored: Vec<Node>,
    pub b_prime: Weight,
    pub edges_scanned: usize,
    pub heap_pushes: usize,
}

/// Multi-source Dijkstra bounded by `bound`.
pub fn bounded_multi_source_shortest_paths(
    g: &Graph,
    sources: &[(Node, Weight)],
    bound: Weight,
) -> BmsspResult {
    let n = g.len();
    let mut dist = vec![Weight::MAX; n];
    let mut heap: BinaryHeap<Reverse<Entry>> = BinaryHeap::new();
    let mut explored = Vec::<Node>::new();

    for &(s, d0) in sources {
        if s < n && d0 < bound && d0 < dist[s] {
            dist[s] = d0;
            heap.push(Reverse(Entry{ d: d0, v: s }));
        }
    }
    let mut b_prime = Weight::MAX;
    let mut edges_scanned: usize = 0;
    let mut heap_pushes: usize = 0;

    while let Some(Reverse(Entry{ d, v })) = heap.pop() {
        if d != dist[v] { continue; }
    if d >= bound { b_prime = d; break; }

        explored.push(v);
        for &(to, w) in &g.adj[v] {
            edges_scanned += 1;
            let nd = d.saturating_add(w);
            if nd < dist[to] && nd < bound {
                dist[to] = nd;
                heap.push(Reverse(Entry{ d: nd, v: to }));
                heap_pushes += 1;
            } else if nd >= bound && nd < b_prime {
                b_prime = nd;
            }
        }
    }

    BmsspResult{ dist, explored, b_prime, edges_scanned, heap_pushes }
}

/// Parallel variant: split sources into `threads` shards, run bounded BMSSP per shard, and merge.
/// Correct distances are the pointwise min over shard distances; b' is min over shard b'.
/// Note: may do extra work vs true multi-source but is embarrassingly parallel when k is large.
pub fn bmssp_sharded(
    g: &Graph,
    sources: &[(Node, Weight)],
    bound: Weight,
    threads: usize,
) -> BmsspResult {
    let t = threads.max(1).min(sources.len().max(1));
    if t <= 1 { return bounded_multi_source_shortest_paths(g, sources, bound); }
    let mut shards: Vec<Vec<(Node,Weight)>> = vec![Vec::new(); t];
    for (i, &sw) in sources.iter().enumerate() { shards[i % t].push(sw); }

    let mut parts: Vec<BmsspResult> = Vec::with_capacity(t);
    std::thread::scope(|scope| {
        let handles: Vec<_> = shards
            .into_iter()
            .map(|shard| scope.spawn(move || bounded_multi_source_shortest_paths(g, &shard, bound)))
            .collect();
        for h in handles {
            parts.push(h.join().expect("thread panicked"));
        }
    });

    let mut merged = BmsspResult{
        dist: vec![Weight::MAX; g.len()],
        explored: Vec::new(),
        b_prime: Weight::MAX,
        edges_scanned: 0,
        heap_pushes: 0,
    };
    use std::collections::HashSet;
    let mut seen: HashSet<Node> = HashSet::new();
    for r in parts {
        for (i, &d) in r.dist.iter().enumerate() { if d < merged.dist[i] { merged.dist[i] = d; } }
        for &v in &r.explored { if seen.insert(v) { merged.explored.push(v); } }
        if r.b_prime < merged.b_prime { merged.b_prime = r.b_prime; }
        merged.edges_scanned += r.edges_scanned;
        merged.heap_pushes += r.heap_pushes;
    }
    merged
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::{rngs::StdRng, Rng, SeedableRng};
    fn line_graph(n: usize, w: Weight) -> Graph {
        let mut g = Graph::new(n);
        for i in 0..n-1 {
            g.add_edge(i, i+1, w);
            g.add_edge(i+1, i, w);
        }
        g
    }

    fn random_graph_er(n: usize, p: f64, maxw: u32, seed: u64) -> Graph {
        let mut rng = StdRng::seed_from_u64(seed);
        let mut g = Graph::new(n);
        for u in 0..n {
            for v in 0..n {
                if u == v { continue; }
                if rng.gen::<f64>() < p {
                    let w = rng.gen_range(1..=maxw) as u64;
                    g.add_edge(u, v, w);
                }
            }
        }
        g
    }

    fn random_graph_ba(n: usize, m0: usize, m: usize, maxw: u32, seed: u64) -> Graph {
        let mut rng = StdRng::seed_from_u64(seed);
        let mut g = Graph::new(n);
        // Preferential attachment via endpoint multiplicities
        let mut ends: Vec<usize> = Vec::new();
        let start = m0.max(1).min(n);
        for u in 0..start {
            for v in 0..start { if u != v { g.add_edge(u, v, 1); ends.push(u); } }
        }
        for u in start..n {
            for _ in 0..m {
                let t = if ends.is_empty() { rng.gen_range(0..u) } else { ends[rng.gen_range(0..ends.len())] };
                let w = rng.gen_range(1..=maxw) as u64;
                g.add_edge(u, t, w);
                ends.push(t);
                ends.push(u);
            }
        }
        g
    }

    fn pick_sources(n: usize, k: usize, seed: u64) -> Vec<(usize,u64)> {
        let mut rng = StdRng::seed_from_u64(seed ^ 0x9E37_79B9_7F4A_7C15);
        let mut seen = std::collections::BTreeSet::new();
        let mut out = Vec::with_capacity(k);
        while out.len() < k && seen.len() < n {
            let s = rng.gen_range(0..n);
            if seen.insert(s) { out.push((s, 0)); }
        }
        out
    }

    #[test]
    fn small_bound() {
        let g = line_graph(6, 3);
        let res = bounded_multi_source_shortest_paths(&g, &[(0,0),(5,0)], 7);
    assert_eq!(res.explored.len(), 6);
        assert_eq!(res.dist[0], 0);
        assert_eq!(res.dist[1], 3);
        assert_eq!(res.dist[2], 6);
        assert_eq!(res.dist[5], 0);
        assert_eq!(res.dist[4], 3);
        assert_eq!(res.dist[3], 6);
        assert!(res.b_prime >= 7);
    }

    #[test]
    fn boundary_tightness() {
        let mut g = Graph::new(3);
        g.add_edge(0,1,5);
        g.add_edge(1,2,2);
        let res = bounded_multi_source_shortest_paths(&g, &[(0,0)], 6);
        assert_eq!(res.explored, vec![0,1]);
        assert_eq!(res.dist[2], u64::MAX);
        assert_eq!(res.b_prime, 7);
    }

    #[test]
    fn memory_estimate() {
        let mut g = Graph::new(5);
        g.add_undirected_edge(0,1,1);
        g.add_undirected_edge(1,2,1);
        g.add_undirected_edge(2,3,1);
        g.add_undirected_edge(3,4,1);
        assert!(g.memory_estimate_bytes() > 0);
    }

    #[test]
    fn sharded_equivalence_on_er() {
        let n = 200usize;
        let g = random_graph_er(n, 0.02, 5, 12345);
        let sources = pick_sources(n, 10, 777);
        let b: Weight = 50;

        let r_ref = bounded_multi_source_shortest_paths(&g, &sources, b);
        let r_sh = bmssp_sharded(&g, &sources, b, 4);

        assert_eq!(r_ref.dist.len(), r_sh.dist.len());
        for i in 0..n { assert_eq!(r_ref.dist[i], r_sh.dist[i], "dist mismatch at {}", i); }
        assert_eq!(r_ref.b_prime, r_sh.b_prime);
    }

    #[test]
    fn er_monotonic_with_bound() {
        let n = 150usize;
        let g = random_graph_er(n, 0.03, 7, 9999);
        let sources = pick_sources(n, 8, 2025);
        let b1: Weight = 20; let b2: Weight = 40;
        let r1 = bounded_multi_source_shortest_paths(&g, &sources, b1);
        let r2 = bounded_multi_source_shortest_paths(&g, &sources, b2);
        let f1 = r1.dist.iter().filter(|&&d| d < Weight::MAX).count();
        let f2 = r2.dist.iter().filter(|&&d| d < Weight::MAX).count();
        assert!(f2 >= f1, "more nodes should be settled with larger bound");
        assert!(r1.b_prime == Weight::MAX || r1.b_prime >= b1);
        assert!(r2.b_prime == Weight::MAX || r2.b_prime >= b2);
        if r1.b_prime != Weight::MAX && r2.b_prime != Weight::MAX {
            assert!(r2.b_prime >= r1.b_prime);
        }
    }

    #[test]
    fn ba_runs_and_monotonic() {
        let n = 180usize;
        let g = random_graph_ba(n, 5, 4, 9, 4242);
        let sources = pick_sources(n, 6, 1312);
        let r_small = bounded_multi_source_shortest_paths(&g, &sources, 15);
        let r_big = bounded_multi_source_shortest_paths(&g, &sources, 35);
        assert!(r_small.explored.len() >= 1);
        let f_small = r_small.dist.iter().filter(|&&d| d < Weight::MAX).count();
        let f_big = r_big.dist.iter().filter(|&&d| d < Weight::MAX).count();
        assert!(f_big >= f_small);
        assert!(r_small.b_prime == Weight::MAX || r_small.b_prime >= 15);
        assert!(r_big.b_prime == Weight::MAX || r_big.b_prime >= 35);
    }

    fn make_er(n: usize, p: f64, maxw: u32, seed: u64) -> Graph {
        let mut rng = StdRng::seed_from_u64(seed);
        let mut g = Graph::new(n);
        for u in 0..n {
            for v in 0..n {
                if u == v { continue; }
                if rng.gen::<f64>() < p {
                    let w = rng.gen_range(1..=maxw) as u64;
                    g.add_edge(u, v, w);
                }
            }
        }
        g
    }

    fn make_ba(n: usize, m0: usize, m: usize, maxw: u32, seed: u64) -> Graph {
        let mut rng = StdRng::seed_from_u64(seed);
        let mut g = Graph::new(n);
        let mut ends: Vec<usize> = Vec::new();
        let start = m0.max(1).min(n);
        for u in 0..start { for v in 0..start { if u!=v { g.add_edge(u,v,1); ends.push(u); } } }
        for u in start..n {
            for _ in 0..m {
                let t = if ends.is_empty() { rng.gen_range(0..u) } else { ends[rng.gen_range(0..ends.len())] };
                let w = rng.gen_range(1..=maxw) as u64;
                g.add_edge(u, t, w);
                ends.push(t);
                ends.push(u);
            }
        }
        g
    }

    #[test]
    fn sharded_equivalence_basic() {
        // Small random ER graph; compare single-thread vs sharded
        let g = make_er(200, 0.02, 10, 123);
        let sources: Vec<(usize, u64)> = (0..10).map(|i| (i * 3 % g.len(), 0)).collect();
        let b: u64 = 50;
        let a = bounded_multi_source_shortest_paths(&g, &sources, b);
        let bres = bmssp_sharded(&g, &sources, b, 4);
        assert_eq!(a.b_prime, bres.b_prime);
        assert_eq!(a.dist.len(), bres.dist.len());
        for i in 0..a.dist.len() { assert_eq!(a.dist[i], bres.dist[i], "node {} differs", i); }
    }

    #[test]
    fn er_sanity_boundaries() {
        let g = make_er(150, 0.03, 7, 7);
        let sources = vec![(0,0), (10,0), (20,0)];
        let b = 25u64;
        let r = bounded_multi_source_shortest_paths(&g, &sources, b);
        // Basic invariants
        assert!(r.b_prime >= b);
        assert!(r.edges_scanned >= r.explored.len());
        // Any popped node must have finite distance < B
        for &v in &r.explored { assert!(r.dist[v] < b); }
    }

    #[test]
    fn ba_sanity_somework() {
        let g = make_ba(200, 5, 3, 11, 11);
        let sources = vec![(0,0), (50,0), (100,0)];
        let b = 40u64;
        let r = bounded_multi_source_shortest_paths(&g, &sources, b);
        assert!(r.b_prime >= b);
        // Should visit at least the sources and some neighbors in a connected-ish BA
        assert!(r.explored.len() >= sources.len());
    }
}
