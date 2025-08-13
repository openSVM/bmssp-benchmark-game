#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <errno.h>

// Minimal binary heap for (d,v)
typedef struct { uint64_t d; uint32_t v; } Entry;
typedef struct { Entry* data; size_t n, cap; } Heap;
static void heap_init(Heap* h){ h->data=NULL; h->n=0; h->cap=0; }
static void heap_push(Heap* h, Entry e){ if(h->n==h->cap){ h->cap=h->cap? h->cap*2:64; h->data=realloc(h->data,h->cap*sizeof(Entry)); } size_t i=h->n++; while(i){ size_t p=(i-1)/2; if(h->data[p].d<=e.d) break; h->data[i]=h->data[p]; i=p; } h->data[i]=e; }
static int heap_pop(Heap* h, Entry* out){ if(!h->n) return 0; *out=h->data[0]; Entry x=h->data[--h->n]; size_t i=0; while(1){ size_t l=i*2+1, r=l+1; if(l>=h->n) break; size_t m=(r<h->n && h->data[r].d<h->data[l].d)? r:l; if(h->data[m].d>=x.d) break; h->data[i]=h->data[m]; i=m; } h->data[i]=x; return 1; }

// Graph CSR
typedef struct { uint32_t to; uint64_t w; } Edge;
typedef struct { uint32_t* head; Edge* edges; size_t n, m; } Graph;

static void push_edge(Graph* g, Edge e, size_t* cap){
    if(g->m >= *cap){ *cap = (*cap? *cap*2 : 1024); g->edges = realloc(g->edges, (*cap)*sizeof(Edge)); }
    g->edges[g->m++] = e;
}

static Graph make_grid(uint32_t rows, uint32_t cols, uint32_t maxw, uint64_t seed){
    srand((unsigned)seed);
    uint32_t n = rows*cols; Graph g={0}; g.n=n; g.head=calloc(n+1,sizeof(uint32_t));
    // estimate edges
    size_t m_est = (size_t)rows*(cols-1) + (size_t)cols*(rows-1);
    size_t cap = m_est*2+4; if(cap<1024) cap=1024; g.edges = malloc(cap*sizeof(Edge));
    #define IDX(r,c) ((r)*cols+(c))
    for(uint32_t r=0;r<rows;r++) for(uint32_t c=0;c<cols;c++){
        uint32_t u=IDX(r,c);
        if(r+1<rows){ push_edge(&g, (Edge){ IDX(r+1,c), (uint64_t)(rand()%maxw+1) }, &cap); }
        if(c+1<cols){ push_edge(&g, (Edge){ IDX(r,c+1), (uint64_t)(rand()%maxw+1) }, &cap); }
        if(r>0){ push_edge(&g, (Edge){ IDX(r-1,c), (uint64_t)(rand()%maxw+1) }, &cap); }
        if(c>0){ push_edge(&g, (Edge){ IDX(r,c-1), (uint64_t)(rand()%maxw+1) }, &cap); }
        g.head[u+1]=(uint32_t)g.m;
    }
    return g;
}

static Graph make_er(uint32_t n, double p, uint32_t maxw, uint64_t seed){
    srand((unsigned)seed);
    Graph g={0}; g.n=n; g.head=calloc(n+1,sizeof(uint32_t));
    size_t cap = (size_t)(n*n*p*1.1 + 16);
    if(cap<1024) cap=1024; g.edges = malloc(cap*sizeof(Edge));
    for(uint32_t u=0; u<n; ++u){
        for(uint32_t v=0; v<n; ++v){ if(u==v) continue; double r = (double)rand() / (double)RAND_MAX; if(r < p){ push_edge(&g, (Edge){ v, (uint64_t)(rand()%maxw+1) }, &cap); } }
        g.head[u+1] = (uint32_t)g.m;
    }
    return g;
}

static Graph make_ba(uint32_t n, uint32_t m0, uint32_t m_each, uint32_t maxw, uint64_t seed){
    srand((unsigned)seed);
    Graph g={0}; g.n=n; g.head=calloc(n+1,sizeof(uint32_t));
    size_t cap = (size_t)n * (m_each? m_each:1) * 2 + 1024; g.edges = malloc(cap*sizeof(Edge));
    uint32_t start = m0? (m0>n? n: m0) : 1;
    uint32_t* ends = NULL; size_t ends_len=0, ends_cap=0;
    #define ENDS_PUSH(x) do{ if(ends_len>=ends_cap){ ends_cap = ends_cap? ends_cap*2 : 1024; ends = realloc(ends, ends_cap*sizeof(uint32_t)); } ends[ends_len++] = (x); }while(0)
    // initial clique
    for(uint32_t u=0; u<start; ++u){
        for(uint32_t v=0; v<start; ++v){ if(u==v) continue; push_edge(&g, (Edge){ v, (uint64_t)(rand()%maxw+1) }, &cap); ENDS_PUSH(u); }
        g.head[u+1] = (uint32_t)g.m;
    }
    for(uint32_t u=start; u<n; ++u){
        for(uint32_t j=0; j<m_each; ++j){
            uint32_t t;
            if(ends_len==0) t = (u==0? 0 : (uint32_t)(rand()%u));
            else t = ends[(size_t)(rand()%ends_len)];
            push_edge(&g, (Edge){ t, (uint64_t)(rand()%maxw+1) }, &cap);
            ENDS_PUSH(t); ENDS_PUSH(u);
        }
        g.head[u+1] = (uint32_t)g.m;
    }
    free(ends);
    return g;
}

static void free_graph(Graph* g){ free(g->head); free(g->edges); }

static int read_graph_file(const char* path, Graph* out){
    FILE* f = fopen(path, "r"); if(!f) return -1;
    size_t n=0, m=0; if(fscanf(f, "%zu %zu", &n, &m) != 2){ fclose(f); return -2; }
    out->n = (uint32_t)n; out->m = 0; out->head = calloc(n+1, sizeof(uint32_t)); size_t cap = m? m:1024; out->edges = malloc(cap*sizeof(Edge));
    for(size_t i=0;i<m;i++){
        unsigned long long uu,vv,ww; if(fscanf(f, "%llu %llu %llu", &uu, &vv, &ww) != 3){ fclose(f); return -3; }
        if(out->m >= cap){ cap = cap*2; out->edges = realloc(out->edges, cap*sizeof(Edge)); }
        out->edges[out->m++] = (Edge){ (uint32_t)vv, (uint64_t)ww };
        if((size_t)uu+1 <= n && out->head[uu+1] < out->m) out->head[uu+1] = (uint32_t)out->m;
    }
    // Fix head to be non-decreasing
    for(size_t i=1;i<=n;i++){ if(out->head[i] < out->head[i-1]) out->head[i] = out->head[i-1]; }
    fclose(f); return 0;
}

static int read_sources_file(const char* path, uint32_t** out, uint32_t* k){
    FILE* f = fopen(path, "r"); if(!f) return -1;
    unsigned long long kk=0; if(fscanf(f, "%llu", &kk) != 1){ fclose(f); return -2; }
    *k = (uint32_t)kk; *out = malloc((*k) * sizeof(uint32_t));
    for(uint32_t i=0;i<*k;i++){
        unsigned long long s,d0; if(fscanf(f, "%llu %llu", &s, &d0) != 2){ fclose(f); return -3; }
        (*out)[i] = (uint32_t)s;
    }
    fclose(f); return 0;
}

// timing helper
static uint64_t now_ns(){
    struct timespec ts; timespec_get(&ts, TIME_UTC); return (uint64_t)ts.tv_sec*1000000000ull + (uint64_t)ts.tv_nsec;
}

static void pick_sources(uint32_t n, uint32_t k, uint64_t seed, uint32_t* out){ srand((unsigned)(seed^0x9E3779B9)); uint8_t* used=calloc(n,1); uint32_t c=0; while(c<k){ uint32_t s=rand()%n; if(!used[s]){ used[s]=1; out[c++]=s; } } free(used); }

int main(int argc, char** argv){
    // parse args: graph grid|er|ba
    char graph[8] = "grid";
    uint32_t rows=50, cols=50, k=16, maxw=100, m0=5, m_each=5, n=10000; double p=0.0005;
    uint64_t B=200, seed=42; int trials=5; const char* graph_file=NULL; const char* sources_file=NULL;
    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"--graph")) { strncpy(graph, argv[++i], sizeof(graph)-1); graph[sizeof(graph)-1]='\0'; }
        else if(!strcmp(argv[i],"--rows")) rows=atoi(argv[++i]);
        else if(!strcmp(argv[i],"--cols")) cols=atoi(argv[++i]);
        else if(!strcmp(argv[i],"--n")) n=atoi(argv[++i]);
        else if(!strcmp(argv[i],"--p")) p=strtod(argv[++i], NULL);
        else if(!strcmp(argv[i],"--m0")) m0=atoi(argv[++i]);
        else if(!strcmp(argv[i],"--m")) m_each=atoi(argv[++i]);
        else if(!strcmp(argv[i],"--k")) k=atoi(argv[++i]);
        else if(!strcmp(argv[i],"--B")) B=strtoull(argv[++i],NULL,10);
        else if(!strcmp(argv[i],"--seed")) seed=strtoull(argv[++i],NULL,10);
        else if(!strcmp(argv[i],"--trials")) trials=atoi(argv[++i]);
        else if(!strcmp(argv[i],"--maxw")) maxw=atoi(argv[++i]);
        else if(!strcmp(argv[i],"--graph-file")) graph_file=argv[++i];
        else if(!strcmp(argv[i],"--sources-file")) sources_file=argv[++i];
    }
    Graph g; const char* gname = strcmp(graph, "er")==0? "er" : (strcmp(graph, "ba")==0? "ba":"grid");
    if(graph_file){ if(read_graph_file(graph_file, &g) != 0){ fprintf(stderr, "failed to read graph file %s: %s\n", graph_file, strerror(errno)); return 1; } }
    else if(!strcmp(graph,"grid")) { g = make_grid(rows, cols, maxw, seed); }
    else if(!strcmp(graph,"er")) { g = make_er(n, p, maxw, seed); }
    else if(!strcmp(graph,"ba")) { g = make_ba(n, m0, m_each, maxw, seed); }
    else { g = make_grid(rows, cols, maxw, seed); }
    uint32_t n_nodes=g.n; uint64_t mem = (uint64_t)n_nodes*sizeof(uint64_t) + (uint64_t)g.m*(sizeof(Edge));
    uint64_t* dist = malloc((size_t)n_nodes*sizeof(uint64_t));
    uint32_t* sources = NULL;
    if(sources_file){ if(read_sources_file(sources_file, &sources, &k) != 0){ fprintf(stderr, "failed to read sources file %s: %s\n", sources_file, strerror(errno)); free_graph(&g); return 1; } }
    else { sources = malloc((size_t)k*sizeof(uint32_t)); pick_sources(n_nodes, k, seed, sources); }

    for(int t=0;t<trials;t++){
    for(uint32_t i=0;i<n_nodes;i++) dist[i]=UINT64_MAX;
        Heap h; heap_init(&h);
        for(uint32_t i=0;i<k;i++){ uint32_t s=sources[i]; dist[s]=0; heap_push(&h, (Entry){0,s}); }
        uint64_t b_prime = UINT64_MAX; uint32_t popped=0; uint32_t heap_pushes=0; uint32_t edges_scanned=0;
    uint64_t t0 = now_ns();
        Entry cur;
        while(heap_pop(&h,&cur)){
            uint64_t d=cur.d; uint32_t v=cur.v; if(d!=dist[v]) continue; if(d>=B){ b_prime=d; break; }
            popped++;
            uint32_t beg=g.head[v], end=g.head[v+1];
            for(uint32_t ei=beg; ei<end; ei++){
                edges_scanned++;
                uint32_t to=g.edges[ei].to; uint64_t nd=d + g.edges[ei].w; if(nd<dist[to] && nd<B){ dist[to]=nd; heap_push(&h, (Entry){nd,to}); heap_pushes++; }
                else if(nd>=B && nd<b_prime) b_prime=nd;
            }
        }
    uint64_t ns = now_ns() - t0;
    printf("{\"impl\":\"c-bmssp\",\"lang\":\"C\",\"graph\":\"%s\",\"n\":%u,\"m\":%zu,\"k\":%u,\"B\":%llu,\"seed\":%llu,\"time_ns\":%llu,\"popped\":%u,\"edges_scanned\":%u,\"heap_pushes\":%u,\"B_prime\":%llu,\"mem_bytes\":%llu}\n",
           gname, n_nodes,(size_t)g.m,k,(unsigned long long)B,(unsigned long long)(seed+t),(unsigned long long)ns,popped,edges_scanned,heap_pushes,(unsigned long long)b_prime,(unsigned long long)mem);
        free(h.data);
    }
    free(sources); free(dist); free_graph(&g);
    return 0;
}
