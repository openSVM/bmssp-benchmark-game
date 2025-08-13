import std/[times, strformat, strutils, math, random, os]

type
  Edge = tuple[to: int, w: uint64]
  Graph = object
    head: seq[int]
    edges: seq[Edge]
    n: int

proc makeGrid(rows, cols: int, maxw: int, seed: uint64): Graph =
  randomize(seed.int)
  let n = rows*cols
  result.n = n
  result.head = newSeq[int](n+1)
  result.edges = newSeq[Edge]()
  var m = 0
  for r in 0..<rows:
    for c in 0..<cols:
      let u = r*cols + c
      if r+1 < rows:
        result.edges.add(( (r+1)*cols + c, (rand(maxw-1)+1).uint64 )); inc m
      if c+1 < cols:
        result.edges.add(( r*cols + (c+1), (rand(maxw-1)+1).uint64 )); inc m
      if r > 0:
        result.edges.add(( (r-1)*cols + c, (rand(maxw-1)+1).uint64 )); inc m
      if c > 0:
        result.edges.add(( r*cols + (c-1), (rand(maxw-1)+1).uint64 )); inc m
      result.head[u+1] = m

proc makeER(n: int, p: float, maxw: int, seed: uint64): Graph =
  randomize(seed.int)
  result.n = n
  result.head = newSeq[int](n+1)
  result.edges = newSeq[Edge]()
  var m = 0
  for u in 0..<n:
    for v in 0..<n:
      if u == v: continue
      if rand(1.0) < p:
        result.edges.add((v, (rand(maxw-1)+1).uint64)); inc m
    result.head[u+1] = m

proc makeBA(n, m0, m: int, maxw: int, seed: uint64): Graph =
  randomize(seed.int)
  result.n = n
  result.head = newSeq[int](n+1)
  result.edges = newSeq[Edge]()
  var ends: seq[int] = @[]
  let start = max(1, min(m0, n))
  var mm = 0
  # seed clique outbound edges per u
  for u in 0..<start:
    for v in 0..<start:
      if u != v:
        result.edges.add((v, 1'u64)); inc mm
    result.head[u+1] = mm
    # approximate degree weighting: add u repeated (start-1) times
    if start > 1:
      for _ in 0 ..< (start-1):
        ends.add u
  for u in start..<n:
    var i = 0
    while i < m:
      let t = if ends.len == 0: rand(u-1) else: ends[rand(ends.high)]
      let w = (rand(maxw-1)+1).uint64
      result.edges.add((t, w)); inc mm
      i += 1
      ends.add t; ends.add u
    result.head[u+1] = mm

proc pickSources(n, k: int, seed: uint64): seq[int] =
  let maxI = cast[uint64](high(int))
  let s = (seed xor 0x9E3779B97F4A7C15'u64) mod (maxI + 1'u64)
  randomize(int(s))
  result = @[]
  var used = newSeq[bool](n)
  while result.len < k:
    let s = rand(n-1)
    if not used[s]: used[s]=true; result.add s

import std/heapqueue

type Entry = tuple[d: uint64, v: int]
proc `<`(a,b: Entry): bool = a.d < b.d or (a.d == b.d and a.v < b.v)

proc bmssp(g: Graph, sources: seq[int], B: uint64): tuple[popped:int, edges:int, pushes:int, bprime:uint64, timeNs:uint64, mbytes:uint64] =
  var dist = newSeq[uint64](g.n)
  for i in 0..<g.n: dist[i] = high(uint64)
  var h = initHeapQueue[Entry]()
  for s in sources:
    dist[s] = 0'u64
    h.push (0'u64, s)
  var bprime = high(uint64)
  var popped = 0
  var edges = 0
  var pushes = 0
  let t0 = epochTime()
  while h.len > 0:
    let (d,v) = h.pop()
    if d != dist[v]: continue
    if d >= B: bprime = d; break
    inc popped
    for ei in g.head[v] ..< g.head[v+1]:
      inc edges
      let (to, w) = g.edges[ei]
      let nd = d + w
      if nd < dist[to] and nd < B:
        dist[to] = nd
        h.push (nd, to)
        inc pushes
      elif nd >= B and nd < bprime:
        bprime = nd
  let ns = ((epochTime()-t0) * 1e9).uint64
  let mem = (g.n.uint64 * sizeof(uint64).uint64) + (g.edges.len.uint64 * (sizeof(int).uint64 + sizeof(uint64).uint64))
  return (popped, edges, pushes, bprime, ns, mem)

when isMainModule:
  var graph = "grid"
  var rows = 50
  var cols = 50
  var n = 1000
  var p = 0.0005
  var m0 = 5
  var m = 5
  var k = 16
  var B: uint64 = 200
  var seed: uint64 = 42
  var trials = 5
  var maxw = 100
  var i = 1
  while i < paramCount():
    let a = paramStr(i)
    if a == "--graph": inc i; graph = paramStr(i)
    if a == "--rows": inc i; rows = parseInt(paramStr(i))
    elif a == "--cols": inc i; cols = parseInt(paramStr(i))
    elif a == "--n": inc i; n = parseInt(paramStr(i))
    elif a == "--p": inc i; p = parseFloat(paramStr(i))
    elif a == "--m0": inc i; m0 = parseInt(paramStr(i))
    elif a == "--m": inc i; m = parseInt(paramStr(i))
    elif a == "--k": inc i; k = parseInt(paramStr(i))
    elif a == "--B": inc i; B = parseBiggestUInt(paramStr(i))
    elif a == "--seed": inc i; seed = parseBiggestUInt(paramStr(i))
    elif a == "--trials": inc i; trials = parseInt(paramStr(i))
    elif a == "--maxw": inc i; maxw = parseInt(paramStr(i))
    inc i
  var g: Graph
  var gname = graph
  if graph == "grid": g = makeGrid(rows, cols, maxw, seed)
  elif graph == "er": g = makeER(n, p, maxw, seed)
  elif graph == "ba": g = makeBA(n, m0, m, maxw, seed)
  else: g = makeGrid(rows, cols, maxw, seed); gname = "grid"
  let src = pickSources(g.n, k, seed)
  for t in 0..<trials:
    let (popped, edges, pushes, bprime, ns, mem) = bmssp(g, src, B)
    echo "{" &
         "\"impl\":\"nim-bmssp\"," &
         "\"lang\":\"Nim\"," &
         "\"graph\":\"" & gname & "\"," &
         "\"n\":" & $g.n & "," &
         "\"m\":" & $g.edges.len & "," &
         "\"k\":" & $k & "," &
         "\"B\":" & $B & "," &
         "\"seed\":" & $(seed.uint64 + t.uint64) & "," &
         "\"time_ns\":" & $ns & "," &
         "\"popped\":" & $popped & "," &
         "\"edges_scanned\":" & $edges & "," &
         "\"heap_pushes\":" & $pushes & "," &
         "\"B_prime\":" & $bprime & "," &
         "\"mem_bytes\":" & $mem &
         "}"
