import java.util.*;

class Edge {
    final int to;
    final long w;
    
    Edge(int to, long w) {
        this.to = to;
        this.w = w;
    }
}

class Entry implements Comparable<Entry> {
    final long d;
    final int v;
    
    Entry(long d, int v) {
        this.d = d;
        this.v = v;
    }
    
    @Override
    public int compareTo(Entry other) {
        int cd = Long.compare(this.d, other.d);
        return cd != 0 ? cd : Integer.compare(this.v, other.v);
    }
}

class Graph {
    final int n;
    final List<Edge>[] adj;
    
    @SuppressWarnings("unchecked")
    Graph(int n) {
        this.n = n;
        this.adj = new ArrayList[n];
        for (int i = 0; i < n; i++) {
            this.adj[i] = new ArrayList<>();
        }
    }
    
    void addUndirected(int u, int v, long w) {
        adj[u].add(new Edge(v, w));
        adj[v].add(new Edge(u, w));
    }
    
    int m() {
        int count = 0;
        for (int i = 0; i < n; i++) {
            count += adj[i].size();
        }
        return count;
    }
}

class Result {
    final long[] dist;
    final int explored;
    final long bPrime;
    final long edgesScanned;
    final long heapPushes;
    
    Result(long[] dist, int explored, long bPrime, long edgesScanned, long heapPushes) {
        this.dist = dist;
        this.explored = explored;
        this.bPrime = bPrime;
        this.edgesScanned = edgesScanned;
        this.heapPushes = heapPushes;
    }
}

class Source {
    final int node;
    final long offset;
    
    Source(int node, long offset) {
        this.node = node;
        this.offset = offset;
    }
}

class Config {
    String graph = "";
    int rows = 0;
    int cols = 0;
    int n = 0;
    double p = 0.0;
    int m0 = 5;
    int m = 5;
    int k = 1;
    long B = 0L;
    int trials = 1;
    long seed = 1L;
    int maxw = 100;
}

public class Main {
    
    static Result bmssp(Graph g, List<Source> sources, long B) {
        int n = g.n;
        long[] dist = new long[n];
        Arrays.fill(dist, Long.MAX_VALUE);
        PriorityQueue<Entry> pq = new PriorityQueue<>();
        int explored = 0;
        long edgesScanned = 0L;
        long pushes = 0L;
        long bPrime = Long.MAX_VALUE;
        
        for (Source src : sources) {
            int s = src.node;
            long d0 = src.offset;
            if (s >= 0 && s < n && d0 < B && d0 < dist[s]) {
                dist[s] = d0;
                pq.add(new Entry(d0, s));
            }
        }
        
        while (true) {
            Entry e = pq.poll();
            if (e == null) break;
            if (e.d != dist[e.v]) continue;
            if (e.d >= B) {
                bPrime = Math.min(bPrime, e.d);
                break;
            }
            explored++;
            for (Edge ed : g.adj[e.v]) {
                edgesScanned++;
                long nd = e.d + ed.w;
                if (nd < dist[ed.to] && nd < B) {
                    dist[ed.to] = nd;
                    pq.add(new Entry(nd, ed.to));
                    pushes++;
                } else if (nd >= B && nd < bPrime) {
                    bPrime = nd;
                }
            }
        }
        
        return new Result(dist, explored, bPrime, edgesScanned, pushes);
    }
    
    static Graph makeGrid(int rows, int cols, Random rng, int maxw) {
        int n = rows * cols;
        Graph g = new Graph(n);
        
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                int u = r * cols + c;
                if (r + 1 < rows) {
                    int v = (r + 1) * cols + c;
                    long w = rng.nextInt(Math.max(1, maxw)) + 1;
                    g.addUndirected(u, v, w);
                }
                if (c + 1 < cols) {
                    int v = r * cols + (c + 1);
                    long w = rng.nextInt(Math.max(1, maxw)) + 1;
                    g.addUndirected(u, v, w);
                }
            }
        }
        return g;
    }
    
    static Graph makeER(int n, double p, Random rng, int maxw) {
        Graph g = new Graph(n);
        for (int u = 0; u < n; u++) {
            for (int v = u + 1; v < n; v++) {
                if (rng.nextDouble() < p) {
                    long w = rng.nextInt(Math.max(1, maxw)) + 1;
                    g.addUndirected(u, v, w);
                }
            }
        }
        return g;
    }
    
    static Graph makeBA(int n, int m0, int m, Random rng, int maxw) {
        Graph g = new Graph(n);
        int[] deg = new int[n];
        
        // start with m0 in a chain
        for (int u = 0; u < m0 - 1; u++) {
            long w = rng.nextInt(Math.max(1, maxw)) + 1;
            g.addUndirected(u, u + 1, w);
            deg[u]++;
            deg[u + 1]++;
        }
        
        int sumDeg = 0;
        for (int i = 0; i < n; i++) sumDeg += deg[i];
        
        for (int u = m0; u < n; u++) {
            int added = 0;
            Set<Integer> chosen = new HashSet<>();
            while (added < m) {
                double r = rng.nextDouble() * Math.max(sumDeg, 1.0);
                double acc = 0.0;
                int v = 0;
                while (v < u) {
                    acc += deg[v];
                    if (acc >= r) break;
                    v++;
                }
                if (v == u || chosen.contains(v)) continue;
                long w = rng.nextInt(Math.max(1, maxw)) + 1;
                g.addUndirected(u, v, w);
                deg[u]++;
                deg[v]++;
                sumDeg += 2;
                chosen.add(v);
                added++;
            }
        }
        
        return g;
    }
    
    static List<Source> pickSources(int n, int k, Random rng) {
        Set<Integer> seen = new HashSet<>();
        List<Source> out = new ArrayList<>();
        while (out.size() < k && seen.size() < n) {
            int s = rng.nextInt(n);
            if (seen.add(s)) {
                out.add(new Source(s, 0L));
            }
        }
        return out;
    }
    
    static Config parseArgs(String[] args) {
        Config cfg = new Config();
        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--graph":
                    cfg.graph = args[++i];
                    break;
                case "--rows":
                    cfg.rows = Integer.parseInt(args[++i]);
                    break;
                case "--cols":
                    cfg.cols = Integer.parseInt(args[++i]);
                    break;
                case "--n":
                    cfg.n = Integer.parseInt(args[++i]);
                    break;
                case "--p":
                    cfg.p = Double.parseDouble(args[++i]);
                    break;
                case "--k":
                    cfg.k = Integer.parseInt(args[++i]);
                    break;
                case "--B":
                    cfg.B = Long.parseLong(args[++i]);
                    break;
                case "--trials":
                    cfg.trials = Integer.parseInt(args[++i]);
                    break;
                case "--seed":
                    cfg.seed = Long.parseLong(args[++i]);
                    break;
                case "--maxw":
                    cfg.maxw = Integer.parseInt(args[++i]);
                    break;
                case "--m0":
                    cfg.m0 = Integer.parseInt(args[++i]);
                    break;
                case "--m":
                    cfg.m = Integer.parseInt(args[++i]);
                    break;
                case "--json":
                    // ignored flag for compatibility
                    break;
            }
        }
        return cfg;
    }
    
    static String jsonLine(String impl, String lang, String graph, int n, int m, int k, long B, 
                          long seed, long timeNs, int popped, long scanned, long pushes, 
                          long bprime, long memBytes) {
        return String.format(
            "{\"impl\":\"%s\",\"lang\":\"%s\",\"graph\":\"%s\",\"n\":%d,\"m\":%d,\"k\":%d," +
            "\"B\":%d,\"seed\":%d,\"time_ns\":%d,\"popped\":%d,\"edges_scanned\":%d," +
            "\"heap_pushes\":%d,\"B_prime\":%d,\"mem_bytes\":%d}",
            impl, lang, graph, n, m, k, B, seed, timeNs, popped, scanned, pushes, bprime, memBytes
        );
    }
    
    public static void main(String[] args) {
        Config cfg = parseArgs(args);
        
        for (int t = 0; t < cfg.trials; t++) {
            Random rng = new Random(cfg.seed + t);
            Graph g;
            
            switch (cfg.graph) {
                case "grid":
                    g = makeGrid(cfg.rows, cfg.cols, rng, cfg.maxw);
                    break;
                case "er":
                    g = makeER(cfg.n, cfg.p, rng, cfg.maxw);
                    break;
                case "ba":
                    g = makeBA(cfg.n, cfg.m0, cfg.m, rng, cfg.maxw);
                    break;
                default:
                    return;
            }
            
            List<Source> sources = pickSources(g.n, cfg.k, rng);
            long t0 = System.nanoTime();
            Result res = bmssp(g, sources, cfg.B);
            long t1 = System.nanoTime();
            long timeNs = t1 - t0;
            long memBytes = (long) g.m() * 16L + (long) g.n * 16L;
            
            String line = jsonLine(
                "java-bmssp", "Java", cfg.graph,
                g.n, g.m(), cfg.k, cfg.B, cfg.seed + t,
                timeNs, res.explored, res.edgesScanned,
                res.heapPushes, res.bPrime == Long.MAX_VALUE ? cfg.B : res.bPrime,
                memBytes
            );
            System.out.println(line);
        }
    }
}
