use bmssp::*;
use criterion::{criterion_group, criterion_main, Criterion, black_box};
use rand::{rngs::StdRng, Rng, SeedableRng};

fn random_graph(n: usize, m: usize, seed: u64) -> Graph {
    let mut rng = StdRng::seed_from_u64(seed);
    let mut g = Graph::new(n);
    for _ in 0..m {
        let u = rng.gen_range(0..n);
        let v = rng.gen_range(0..n);
        if u == v { continue; }
        let w: u64 = rng.gen_range(1..20);
        g.add_edge(u, v, w);
    }
    g
}

fn bench_bmssp(c: &mut Criterion) {
    let n = 50_000;
    let m = 200_000;
    let g = random_graph(n, m, 42);
    let sources: Vec<(usize, u64)> = (0..32).map(|i| (i * (n/32), 0)).collect();
    let bound: u64 = 300;

    c.bench_function("bmssp_50k_200k_bound300", |b| {
        b.iter(|| {
            let res = bounded_multi_source_shortest_paths(&g, black_box(&sources), black_box(bound));
            black_box(res.explored.len());
        })
    });
}

criterion_group!(benches, bench_bmssp);
criterion_main!(benches);
