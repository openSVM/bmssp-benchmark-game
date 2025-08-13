use bmssp::*;
use rand::{rngs::StdRng, Rng, SeedableRng};
use serde::Serialize;
use std::time::Instant;
use std::path::PathBuf;
use std::fs::File;
use std::io::{BufRead, BufReader};

#[derive(Debug, Clone, Copy)]
enum GraphType { Grid, ER, BA }

#[derive(Serialize)]
struct OutputRow {
    #[serde(rename = "impl")] impl_: &'static str,
    lang: &'static str,
    graph: &'static str,
    n: usize,
    m: usize,
    k: usize,
    #[serde(rename = "B")] b: u64,
    seed: u64,
    threads: usize,
    time_ns: u128,
    popped: usize,
    edges_scanned: usize,
    heap_pushes: usize,
    #[serde(rename = "B_prime")] b_prime: u64,
    mem_bytes: usize,
}

fn parse_args() -> (GraphType, usize, Option<(usize,usize)>, f64, usize, usize, u32, usize, u64, u64, usize, usize, bool, Option<PathBuf>, Option<PathBuf>) {
    // Minimal, no external clap to keep deps small.
    let mut graph = GraphType::ER;
    let mut n: usize = 10_000;
    let mut grid_rc: Option<(usize,usize)> = None;
    let mut rows_opt: Option<usize> = None;
    let mut cols_opt: Option<usize> = None;
    let mut p: f64 = 0.0005;
    let mut m0: usize = 5;
    let mut m_ba: usize = 5;
    let mut maxw: u32 = 100;
    let mut k: usize = 16;
    let mut b: u64 = 500;
    let mut seed: u64 = 42;
    let mut trials: usize = 5;
    let mut threads: usize = 1;
    let mut json: bool = true;
    let mut graph_file: Option<PathBuf> = None;
    let mut sources_file: Option<PathBuf> = None;

    let mut it = std::env::args().skip(1);
    while let Some(a) = it.next() {
        match a.as_str() {
            "--graph" => {
                let v = it.next().expect("--graph value");
                graph = match v.as_str() { "grid" => GraphType::Grid, "er" => GraphType::ER, "ba" => GraphType::BA, _ => panic!("bad graph") };
            }
            "--n" => n = it.next().unwrap().parse().unwrap(),
            "--rows" => { rows_opt = Some(it.next().unwrap().parse().unwrap()); }
            "--cols" => { cols_opt = Some(it.next().unwrap().parse().unwrap()); }
            "--p" => p = it.next().unwrap().parse().unwrap(),
            "--m0" => m0 = it.next().unwrap().parse().unwrap(),
            "--m" => m_ba = it.next().unwrap().parse().unwrap(),
            "--maxw" => maxw = it.next().unwrap().parse().unwrap(),
            "--k" => k = it.next().unwrap().parse().unwrap(),
            "--B" => b = it.next().unwrap().parse().unwrap(),
            "--seed" => seed = it.next().unwrap().parse().unwrap(),
            "--trials" => trials = it.next().unwrap().parse().unwrap(),
            "--threads" => threads = it.next().unwrap().parse().unwrap(),
            "--json" => json = true,
        "--graph-file" => { let v = it.next().expect("--graph-file value"); graph_file = Some(PathBuf::from(v)); }
        "--sources-file" => { let v = it.next().expect("--sources-file value"); sources_file = Some(PathBuf::from(v)); }
            _ => {}
        }
    }
    if rows_opt.is_some() || cols_opt.is_some() { grid_rc = Some((rows_opt.unwrap_or(1), cols_opt.unwrap_or(1))); }
    (graph, n, grid_rc, p, m0, m_ba, maxw, k, b, seed, trials, threads, json, graph_file, sources_file)
}

fn make_grid(rows: usize, cols: usize, maxw: u32, seed: u64) -> Graph {
    let mut rng = StdRng::seed_from_u64(seed);
    let mut g = Graph::new(rows * cols);
    let idx = |r: usize, c: usize| -> usize { r * cols + c };
    for r in 0..rows {
        for c in 0..cols {
            let u = idx(r,c);
            if r + 1 < rows {
                let w = rng.gen_range(1..=maxw) as u64;
                g.add_undirected_edge(u, idx(r+1,c), w);
            }
            if c + 1 < cols {
                let w = rng.gen_range(1..=maxw) as u64;
                g.add_undirected_edge(u, idx(r,c+1), w);
            }
        }
    }
    g
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
    // Simple preferential attachment: maintain list of endpoints with multiplicity
    let mut ends: Vec<usize> = Vec::new();
    let start = m0.max(1).min(n);
    for u in 0..start { for v in 0..start { if u!=v { g.add_edge(u,v,1); ends.push(u); } } }
    for u in start..n {
        for _ in 0..m { // pick endpoints proportional to degree
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
    let mut rng = StdRng::seed_from_u64(seed ^ 0x9E3779B97F4A7C15);
    let mut seen = std::collections::BTreeSet::new();
    let mut out = Vec::with_capacity(k);
    while out.len() < k && seen.len() < n {
        let s = rng.gen_range(0..n);
        if seen.insert(s) { out.push((s,0)); }
    }
    out
}

fn read_graph_from_file(path: &PathBuf) -> std::io::Result<Graph> {
    let f = File::open(path)?;
    let mut it = BufReader::new(f).lines();
    let header = it.next().transpose()?.unwrap_or_default();
    let mut parts = header.split_whitespace();
    let n: usize = parts.next().unwrap_or("0").parse().unwrap_or(0);
    let _m: usize = parts.next().unwrap_or("0").parse().unwrap_or(0);
    let mut g = Graph::new(n);
    for line in it {
        let line = line?;
        if line.trim().is_empty() { continue; }
        let mut ps = line.split_whitespace();
        let u: usize = ps.next().unwrap().parse().unwrap();
        let v: usize = ps.next().unwrap().parse().unwrap();
        let w: u64 = ps.next().unwrap().parse().unwrap();
        g.add_edge(u, v, w);
    }
    Ok(g)
}

fn read_sources_from_file(path: &PathBuf) -> std::io::Result<Vec<(usize,u64)>> {
    let f = File::open(path)?;
    let mut it = BufReader::new(f).lines();
    let header = it.next().transpose()?.unwrap_or_default();
    let k: usize = header.split_whitespace().next().unwrap_or("0").parse().unwrap_or(0);
    let mut out: Vec<(usize,u64)> = Vec::with_capacity(k);
    for line in it {
        let line = line?;
        if line.trim().is_empty() { continue; }
        let mut ps = line.split_whitespace();
        let s: usize = ps.next().unwrap().parse().unwrap();
        let d0: u64 = ps.next().unwrap_or("0").parse().unwrap_or(0);
        out.push((s, d0));
    }
    Ok(out)
}

fn main() {
    let (gtype, n, grid_rc, p, m0, m_ba, maxw, mut k, b, seed, trials, threads, json, graph_file, sources_file) = parse_args();
    let (g, gname): (Graph, &'static str) = if let Some(path) = graph_file.as_ref() {
        (read_graph_from_file(path).expect("failed to read graph file"), match gtype { GraphType::Grid => "grid", GraphType::ER => "er", GraphType::BA => "ba" })
    } else {
        match gtype {
            GraphType::Grid => {
                let (r,c) = grid_rc.unwrap_or_else(||{
                    let side = (n as f64).sqrt() as usize; (side, side.max(1))
                });
                (make_grid(r,c,maxw,seed), "grid")
            }
            GraphType::ER => (make_er(n, p, maxw, seed), "er"),
            GraphType::BA => (make_ba(n, m0, m_ba, maxw, seed), "ba"),
        }
    };
    let n = g.len();
    let m: usize = g.adj.iter().map(|v| v.len()).sum();
    let sources = if let Some(sp) = sources_file.as_ref() {
        let s = read_sources_from_file(sp).expect("failed to read sources file");
        k = s.len();
        s
    } else { pick_sources(n, k, seed) };
    let mem = g.memory_estimate_bytes();

    let mut best: Option<OutputRow> = None;
    for t in 0..trials {
        let start = Instant::now();
    let res = if threads > 1 { bmssp_sharded(&g, &sources, b, threads) } else { bounded_multi_source_shortest_paths(&g, &sources, b) };
        let elapsed = start.elapsed().as_nanos();
        let row = OutputRow{
            impl_: "rust-bmssp",
            lang: "Rust",
            graph: gname,
            n,
            m,
            k: sources.len(),
            b,
            seed: seed + t as u64,
            threads,
            time_ns: elapsed,
            popped: res.explored.len(),
            edges_scanned: res.edges_scanned,
            heap_pushes: res.heap_pushes,
            b_prime: res.b_prime,
            mem_bytes: mem,
        };
        if json { println!("{}", serde_json::to_string(&row).unwrap()); }
        if best.as_ref().map(|b| row.time_ns < b.time_ns).unwrap_or(true) { best = Some(row); }
    }
    // Print best summary to stderr for human glance
    if let Some(b) = best { eprintln!("best ns={} popped={} B'={}", b.time_ns, b.popped, b.b_prime); }
}
