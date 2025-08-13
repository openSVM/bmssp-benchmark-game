require "json"
require "set"

struct Entry
  include Comparable(Entry)
  getter d : UInt64
  getter v : Int32
  def initialize(@d : UInt64, @v : Int32); end
  def <=>(other)
  # min-heap behavior via reverse compare, tie-break by vertex id
  cmp = other.d <=> d
  return cmp unless cmp == 0
  v <=> other.v
  end
end

alias Weight = UInt64

class Graph
  getter adj : Array(Array(Tuple(Int32, Weight)))
  def initialize(n : Int32)
    @adj = Array.new(n) { Array(Tuple(Int32, Weight)).new }
  end
  def len : Int32; @adj.size; end
  def add_edge(u : Int32, v : Int32, w : Weight)
    @adj[u] << {v, w}
  end
  def add_undirected_edge(u : Int32, v : Int32, w : Weight)
    add_edge(u, v, w); add_edge(v, u, w)
  end
  def memory_estimate_bytes : Int64
    n = @adj.size
    m = @adj.sum(&.size)
    edge_bytes = m * (sizeof(Int32) + sizeof(Weight))
    vec_headers = n * 3 * sizeof(Int32)
    outer_vec_header = 3 * sizeof(Int32)
    dist_bytes = n * sizeof(Weight)
    flags_bytes = n * sizeof(UInt8) * 2
    (edge_bytes + vec_headers + outer_vec_header + dist_bytes + flags_bytes).to_i64
  end
end

struct Result
  getter dist : Array(Weight)
  getter explored : Array(Int32)
  getter b_prime : Weight
  getter edges_scanned : Int32
  getter heap_pushes : Int32
  def initialize(@dist : Array(Weight), @explored : Array(Int32), @b_prime : Weight, @edges_scanned : Int32, @heap_pushes : Int32); end
end

def bmssp(g : Graph, sources : Array(Tuple(Int32, Weight)), bound : Weight) : Result
  n = g.len
  dist = Array(Weight).new(n, UInt64::MAX)
  heap = [] of Entry
  explored = [] of Int32
  b_prime = UInt64::MAX
  edges_scanned = 0
  heap_pushes = 0

  sources.each do |(s, d0)|
    if 0 <= s && s < n && d0 < bound && d0 < dist[s]
      dist[s] = d0
      heap << Entry.new(d0, s)
      heap.sort!
    end
  end

  while heap.size > 0
    e = heap.pop
    # heap is sorted ascending by our comparable
    d = e.d; v = e.v
    next if d != dist[v]
    if d >= bound
      b_prime = d
      break
    end
    explored << v
    g.adj[v].each do |(to, w)|
      edges_scanned += 1
      nd = d &+ w
      if nd < dist[to] && nd < bound
        dist[to] = nd
        heap << Entry.new(nd, to)
        heap.sort!
        heap_pushes += 1
      elsif nd >= bound && nd < b_prime
        b_prime = nd
      end
    end
  end

  Result.new(dist, explored, b_prime, edges_scanned, heap_pushes)
end

struct Row
  include JSON::Serializable
  @[JSON::Field(key: "impl")]
  getter impl_name : String
  getter lang : String
  getter graph : String
  getter n : Int32
  getter m : Int32
  getter k : Int32
  @[JSON::Field(key: "B")]
  getter bound : UInt64
  getter seed : UInt64
  getter time_ns : UInt64
  getter popped : Int32
  getter edges_scanned : Int32
  getter heap_pushes : Int32
  @[JSON::Field(key: "B_prime")]
  getter b_prime : UInt64
  getter mem_bytes : Int64
  def initialize(@impl_name, @lang, @graph, @n, @m, @k, @bound, @seed, @time_ns, @popped, @edges_scanned, @heap_pushes, @b_prime, @mem_bytes); end
end

module RNG
  extend self
  def pick_sources(n : Int32, k : Int32, seed : UInt64)
    rng = Random::PCG32.new(seed)
    seen = Set(Int32).new
    out = [] of Tuple(Int32, Weight)
    while out.size < k && seen.size < n
  s = rng.rand(n)
      unless seen.includes?(s)
        seen.add(s)
        out << {s, 0_u64}
      end
    end
    out
  end
end

enum GraphType
  Grid
  ER
  BA
end

record Args,
  gtype : GraphType,
  n : Int32,
  rows : Int32?,
  cols : Int32?,
  p : Float64,
  m0 : Int32,
  m : Int32,
  maxw : Int32,
  k : Int32,
  b : UInt64,
  seed : UInt64,
  trials : Int32,
  json : Bool

def parse_args : Args
  gtype = GraphType::ER
  n = 10_000
  rows = nil.as(Int32?)
  cols = nil.as(Int32?)
  p = 0.0005
  m0 = 5
  m = 5
  maxw = 100
  k = 16
  b : UInt64 = 500_u64
  seed : UInt64 = 42_u64
  trials = 5
  json = true
  i = 0
  argv = ARGV
  while i < argv.size
    case argv[i]
    when "--graph"; i+=1; v=argv[i]; gtype = v == "grid" ? GraphType::Grid : v == "ba" ? GraphType::BA : GraphType::ER
    when "--n"; i+=1; n = argv[i].to_i
    when "--rows"; i+=1; rows = argv[i].to_i
    when "--cols"; i+=1; cols = argv[i].to_i
    when "--p"; i+=1; p = argv[i].to_f
    when "--m0"; i+=1; m0 = argv[i].to_i
    when "--m"; i+=1; m = argv[i].to_i
    when "--maxw"; i+=1; maxw = argv[i].to_i
    when "--k"; i+=1; k = argv[i].to_i
    when "--B"; i+=1; b = argv[i].to_u64
    when "--seed"; i+=1; seed = argv[i].to_u64
    when "--trials"; i+=1; trials = argv[i].to_i
    when "--json"; json = true
    end
    i+=1
  end
  Args.new(gtype, n, rows, cols, p, m0, m, maxw, k, b, seed, trials, json)
end

def make_grid(rows : Int32, cols : Int32, maxw : Int32, seed : UInt64) : Graph
  rng = Random::PCG32.new(seed)
  g = Graph.new(rows * cols)
  idx = ->(r : Int32, c : Int32) { r * cols + c }
  r = 0
  while r < rows
    c = 0
    while c < cols
      u = idx.call(r,c)
      if r + 1 < rows
        w = (rng.rand(maxw) + 1).to_u64
        g.add_undirected_edge(u, idx.call(r+1,c), w)
      end
      if c + 1 < cols
        w = (rng.rand(maxw) + 1).to_u64
        g.add_undirected_edge(u, idx.call(r,c+1), w)
      end
      c+=1
    end
    r+=1
  end
  g
end

def make_er(n : Int32, p : Float64, maxw : Int32, seed : UInt64) : Graph
  rng = Random::PCG32.new(seed)
  g = Graph.new(n)
  u = 0
  while u < n
    v = 0
    while v < n
      if u != v && (rng.rand < p)
        w = (rng.rand(maxw) + 1).to_u64
        g.add_edge(u, v, w)
      end
      v+=1
    end
    u+=1
  end
  g
end

def make_ba(n : Int32, m0 : Int32, m : Int32, maxw : Int32, seed : UInt64) : Graph
  rng = Random::PCG32.new(seed)
  g = Graph.new(n)
  ends = [] of Int32
  start = {m0, 1}.max.clamp(1, n)
  u = 0
  while u < start
    v = 0
    while v < start
      if u != v
        g.add_edge(u, v, 1_u64)
        ends << u
      end
      v+=1
    end
    u+=1
  end
  u = start
  while u < n
    i = 0
    while i < m
  t = ends.empty? ? rng.rand(u) : ends[rng.rand(ends.size)]
  w = (rng.rand(maxw) + 1).to_u64
      g.add_edge(u, t, w)
      ends << t
      ends << u
      i+=1
    end
    u+=1
  end
  g
end

args = parse_args

g = Graph.new(args.n)
gname = "er"
case args.gtype
when GraphType::Grid
  rows = args.rows || Math.sqrt(args.n).to_i
  cols = args.cols || rows
  g = make_grid(rows, cols, args.maxw, args.seed)
  gname = "grid"
when GraphType::ER
  g = make_er(args.n, args.p, args.maxw, args.seed)
  gname = "er"
when GraphType::BA
  g = make_ba(args.n, args.m0, args.m, args.maxw, args.seed)
  gname = "ba"
else
  g = make_er(args.n, args.p, args.maxw, args.seed)
  gname = "er"
end

n = g.len
m = g.adj.sum(&.size)
sources = RNG.pick_sources(n, args.k, args.seed)
mem = g.memory_estimate_bytes

best : Row? = nil
args.trials.times do |t|
  start = Time.monotonic
  res = bmssp(g, sources, args.b)
  ns = (Time.monotonic - start).nanoseconds
  row = Row.new("crystal-bmssp", "Crystal", gname, n, m, sources.size, args.b, args.seed + t.to_u64, ns.to_u64, res.explored.size, res.edges_scanned, res.heap_pushes, res.b_prime, mem)
  if args.json
    puts row.to_json
  end
  if best.nil? || row.time_ns < best.not_nil!.time_ns
    best = row
  end
end
STDERR.puts "best ns=#{best.not_nil!.time_ns} popped=#{best.not_nil!.popped} B'=#{best.not_nil!.b_prime}"
