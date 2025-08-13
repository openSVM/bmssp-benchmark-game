#include <bits/stdc++.h>
using namespace std;
using U64 = unsigned long long; using U32 = uint32_t;
struct Entry{ U64 d; U32 v; bool operator<(Entry const& o) const { if(d!=o.d) return d>o.d; return v>o.v; } };
struct Edge{ U32 to; U64 w; };
struct Graph{ vector<U32> head; vector<Edge> edges; U32 n; size_t m; };

static inline U64 rnd_w(std::mt19937_64 &rng, U32 maxw){ return (U64)(rng() % maxw + 1); }

Graph from_adj(const vector<vector<Edge>>& adj){
    Graph g; g.n = (U32)adj.size(); g.head.assign(g.n+1, 0);
    size_t total = 0; for(auto &v : adj) total += v.size();
    g.edges.reserve(total);
    size_t m = 0; for(U32 u=0; u<g.n; ++u){
        for(const auto &e : adj[u]){ g.edges.push_back(e); ++m; }
        g.head[u+1] = (U32)m;
    }
    g.m = m; return g;
}

Graph from_edge_list(U32 n, const vector<tuple<U32,U32,U64>>& elist){
    Graph g; g.n=n; g.head.assign(n+1,0); g.edges.reserve(elist.size());
    // assume input is arbitrary order; we'll build CSR by grouping by u
    vector<vector<Edge>> adj(n);
    for(auto &t : elist){ U32 u,v; U64 w; tie(u,v,w)=t; if(u<n && v<n){ adj[u].push_back({v,w}); } }
    size_t m=0; for(U32 u=0; u<n; ++u){ for(auto &e: adj[u]){ g.edges.push_back(e); ++m; } g.head[u+1]=(U32)m; }
    g.m=m; return g;
}

Graph make_grid(U32 rows, U32 cols, U32 maxw, U64 seed){
    std::mt19937_64 rng(seed);
    Graph g; g.n=rows*cols; g.head.assign(g.n+1,0);
    size_t m_est = (size_t)rows*(cols-1) + (size_t)cols*(rows-1);
    g.edges.reserve(m_est*2+4);
    auto IDX=[&](U32 r,U32 c){ return r*cols+c; };
    size_t m=0;
    for(U32 r=0;r<rows;r++) for(U32 c=0;c<cols;c++){
        U32 u=IDX(r,c);
        auto rnd = [&]{ return rnd_w(rng, maxw); };
        if(r+1<rows){ g.edges.push_back({IDX(r+1,c), rnd()}); m++; }
        if(c+1<cols){ g.edges.push_back({IDX(r,c+1), rnd()}); m++; }
        if(r>0){ g.edges.push_back({IDX(r-1,c), rnd()}); m++; }
        if(c>0){ g.edges.push_back({IDX(r,c-1), rnd()}); m++; }
        g.head[u+1]=(U32)m;
    }
    g.m=m; return g;
}

Graph make_er(U32 n, double p, U32 maxw, U64 seed){
    std::mt19937_64 rng(seed);
    std::uniform_real_distribution<double> U(0.0, 1.0);
    vector<vector<Edge>> adj(n);
    for(U32 u=0; u<n; ++u){
        for(U32 v=0; v<n; ++v){ if(u==v) continue; if(U(rng) < p){ adj[u].push_back({v, rnd_w(rng, maxw)}); } }
    }
    return from_adj(adj);
}

Graph make_ba(U32 n, U32 m0, U32 m_each, U32 maxw, U64 seed){
    std::mt19937_64 rng(seed);
    vector<vector<Edge>> adj(n);
    vector<U32> ends; ends.reserve((size_t)n * (m_each>0? m_each:1));
    U32 start = std::min<U32>(std::max<U32>(m0, 1), n);
    // initial clique among [0..start)
    for(U32 u=0; u<start; ++u){ for(U32 v=0; v<start; ++v){ if(u==v) continue; adj[u].push_back({v, rnd_w(rng, maxw)}); ends.push_back(u); } }
    for(U32 u=start; u<n; ++u){
        for(U32 j=0; j<m_each; ++j){
            U32 t;
            if(ends.empty()) t = (u==0? 0 : (U32)(rng() % u));
            else t = ends[(size_t)(rng() % ends.size())];
            adj[u].push_back({t, rnd_w(rng, maxw)});
            ends.push_back(t); ends.push_back(u);
        }
    }
    return from_adj(adj);
}

vector<pair<U32,U64>> pick_sources(U32 n, U32 k, U64 seed){
    std::mt19937_64 rng(seed^0x9E3779B97F4A7C15ull);
    vector<char> used(n,0); vector<pair<U32,U64>> out; out.reserve(k);
    while(out.size()<k){ U32 s=(U32)(rng()%n); if(!used[s]){ used[s]=1; out.push_back({s,0}); } }
    return out;
}

int main(int argc, char** argv){
    string graph = "grid"; U32 n=10000, rows=50, cols=50, k=16, maxw=100, m0=5, m_ba=5; double p=0.0005; U64 B=200, seed=42; int trials=5; string graph_file="", sources_file="";
    for(int i=1;i<argc;i++){
        string a=argv[i];
        auto need=[&](string name){ if(i+1>=argc) { cerr<<"missing value for "<<name<<"\n"; exit(1);} return string(argv[++i]); };
        if(a=="--graph") graph=need(a);
        else if(a=="--graph-file") graph_file=need(a);
        else if(a=="--sources-file") sources_file=need(a);
        else if(a=="--n") n=stoul(need(a));
        else if(a=="--rows") rows=stoul(need(a));
        else if(a=="--cols") cols=stoul(need(a));
        else if(a=="--p") p=stod(need(a));
        else if(a=="--m0") m0=stoul(need(a));
        else if(a=="--m") m_ba=stoul(need(a));
        else if(a=="--k") k=stoul(need(a));
        else if(a=="--B") B=stoull(need(a));
        else if(a=="--seed") seed=stoull(need(a));
        else if(a=="--trials") trials=stoi(need(a));
        else if(a=="--maxw") maxw=stoul(need(a));
    }
    Graph g;
    string gname;
    if(!graph_file.empty()){
        ifstream in(graph_file);
        if(!in){ cerr<<"failed to open graph file: "<<graph_file<<"\n"; return 1; }
        U64 nn, mm; in>>nn>>mm; n=(U32)nn; vector<tuple<U32,U32,U64>> elist; elist.reserve((size_t)mm);
        for(U64 i=0;i<mm;i++){ U64 u,v,w; in>>u>>v>>w; elist.emplace_back((U32)u,(U32)v,(U64)w); }
        g = from_edge_list(n, elist); gname = graph;
    } else if(graph=="grid") { g = make_grid(rows, cols, maxw, seed); gname = "grid"; }
    else if(graph=="er") { g = make_er(n, p, maxw, seed); gname = "er"; }
    else if(graph=="ba") { g = make_ba(n, m0, m_ba, maxw, seed); gname = "ba"; }
    else { cerr<<"unsupported graph type: "<<graph<<"\n"; return 1; }
    n=g.n; size_t m=g.m; U64 mem = (U64)n*sizeof(U64) + (U64)m*sizeof(Edge);
    vector<U64> dist(n, ULLONG_MAX);
    vector<pair<U32,U64>> src;
    if(!sources_file.empty()){
        ifstream in(sources_file);
        if(!in){ cerr<<"failed to open sources file: "<<sources_file<<"\n"; return 1; }
        U64 kk; in>>kk; k=(U32)kk; src.reserve(k);
        for(U32 i=0;i<k;i++){ U64 s,d0; in>>s>>d0; src.emplace_back((U32)s,(U64)d0); }
    } else {
        src = pick_sources(n, k, seed);
    }

    for(int t=0;t<trials;t++){
        fill(dist.begin(), dist.end(), ULLONG_MAX);
        priority_queue<Entry> pq; for(auto [s,d0]: src){ if(d0<B){ dist[s]=d0; pq.push({d0,s}); } }
        U64 b_prime = ULLONG_MAX; size_t popped=0, heap_pushes=0, edges_scanned=0;
        auto t0 = chrono::high_resolution_clock::now();
        while(!pq.empty()){
            auto [d,v]=pq.top(); pq.pop(); if(d!=dist[v]) continue; if(d>=B){ b_prime=d; break; }
            popped++;
            for(U32 ei=g.head[v]; ei<g.head[v+1]; ++ei){ edges_scanned++; auto [to,w]=g.edges[ei]; U64 nd=d+w; if(nd<dist[to] && nd<B){ dist[to]=nd; pq.push({nd,to}); heap_pushes++; } else if(nd>=B && nd<b_prime) b_prime=nd; }
        }
        auto t1 = chrono::high_resolution_clock::now();
        U64 ns = chrono::duration_cast<chrono::nanoseconds>(t1-t0).count();
        cout<<"{\"impl\":\"cpp-bmssp\",\"lang\":\"C++\",\"graph\":\""<<gname<<"\",\"n\":"<<n<<",\"m\":"<<m<<",\"k\":"<<k<<",\"B\":"<<B<<",\"seed\":"<<(seed+t)<<",\"time_ns\":"<<ns<<",\"popped\":"<<popped<<",\"edges_scanned\":"<<edges_scanned<<",\"heap_pushes\":"<<heap_pushes<<",\"B_prime\":"<<b_prime<<",\"mem_bytes\":"<<mem<<"}\n";
    }
    return 0;
}
