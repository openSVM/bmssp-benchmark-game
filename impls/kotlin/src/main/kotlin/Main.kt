import java.util.PriorityQueue
import java.util.Random
import kotlin.math.max

data class Edge(val to: Int, val w: Long)
data class Entry(val d: Long, val v: Int): Comparable<Entry> {
    override fun compareTo(other: Entry): Int {
        val cd = d.compareTo(other.d)
        return if (cd != 0) cd else v.compareTo(other.v)
    }
}

class Graph(val n: Int) {
    val adj: Array<MutableList<Edge>> = Array(n) { mutableListOf<Edge>() }
    fun addUndirected(u: Int, v: Int, w: Long) {
        adj[u].add(Edge(v, w))
        adj[v].add(Edge(u, w))
    }
    fun m(): Int = adj.sumOf { it.size }
}

data class Result(
    val dist: LongArray,
    val explored: Int,
    val bPrime: Long,
    val edgesScanned: Long,
    val heapPushes: Long
)

fun bmssp(g: Graph, sources: List<Pair<Int, Long>>, B: Long): Result {
    val n = g.n
    val dist = LongArray(n) { Long.MAX_VALUE }
    val pq = PriorityQueue<Entry>()
    var explored = 0
    var edgesScanned = 0L
    var pushes = 0L
    var bPrime = Long.MAX_VALUE

    for ((s, d0) in sources) {
        if (s in 0 until n && d0 < B && d0 < dist[s]) {
            dist[s] = d0
            pq.add(Entry(d0, s))
        }
    }
    while (true) {
        val e = pq.poll() ?: break
        if (e.d != dist[e.v]) continue
        if (e.d >= B) { bPrime = minOf(bPrime, e.d); break }
        explored += 1
        for (ed in g.adj[e.v]) {
            edgesScanned += 1
            val nd = e.d + ed.w
            if (nd < dist[ed.to] && nd < B) {
                dist[ed.to] = nd
                pq.add(Entry(nd, ed.to))
                pushes += 1
            } else if (nd >= B && nd < bPrime) {
                bPrime = nd
            }
        }
    }
    return Result(dist, explored, bPrime, edgesScanned, pushes)
}

data class Cfg(
    val graph: String,
    val rows: Int = 0,
    val cols: Int = 0,
    val n: Int = 0,
    val p: Double = 0.0,
    val m0: Int = 5,
    val m: Int = 5,
    val k: Int,
    val B: Long,
    val trials: Int,
    val seed: Long,
    val maxw: Int,
)

fun makeGrid(rows: Int, cols: Int, rng: Random, maxw: Int): Graph {
    val n = rows * cols
    val g = Graph(n)
    fun idx(r: Int, c: Int) = r * cols + c
    for (r in 0 until rows) {
        for (c in 0 until cols) {
            val u = idx(r,c)
            if (r+1 < rows) {
                val v = idx(r+1,c)
                val w = (rng.nextInt(max(1, maxw)) + 1).toLong()
                g.addUndirected(u,v,w)
            }
            if (c+1 < cols) {
                val v = idx(r,c+1)
                val w = (rng.nextInt(max(1, maxw)) + 1).toLong()
                g.addUndirected(u,v,w)
            }
        }
    }
    return g
}

fun makeER(n: Int, p: Double, rng: Random, maxw: Int): Graph {
    val g = Graph(n)
    for (u in 0 until n) {
        var v = u + 1
        while (v < n) {
            if (rng.nextDouble() < p) {
                val w = (rng.nextInt(max(1, maxw)) + 1).toLong()
                g.addUndirected(u, v, w)
            }
            v += 1
        }
    }
    return g
}

fun makeBA(n: Int, m0: Int, m: Int, rng: Random, maxw: Int): Graph {
    val g = Graph(n)
    val deg = IntArray(n)
    // start with m0 in a chain
    for (u in 0 until (m0-1)) {
        val w = (rng.nextInt(max(1, maxw)) + 1).toLong()
        g.addUndirected(u, u+1, w)
        deg[u] += 1; deg[u+1] += 1
    }
    var sumDeg = deg.sum()
    for (u in m0 until n) {
        var added = 0
        val chosen = HashSet<Int>()
        while (added < m) {
            val r = rng.nextDouble() * (sumDeg.toDouble().coerceAtLeast(1.0))
            var acc = 0.0
            var v = 0
            while (v < u) {
                acc += deg[v].toDouble()
                if (acc >= r) break
                v += 1
            }
            if (v == u || chosen.contains(v)) continue
            val w = (rng.nextInt(max(1, maxw)) + 1).toLong()
            g.addUndirected(u, v, w)
            deg[u] += 1; deg[v] += 1; sumDeg += 2
            chosen.add(v)
            added += 1
        }
    }
    return g
}

fun pickSources(n: Int, k: Int, rng: Random): List<Pair<Int, Long>> {
    val seen = HashSet<Int>()
    val out = ArrayList<Pair<Int, Long>>()
    while (out.size < k && seen.size < n) {
        val s = rng.nextInt(n)
        if (seen.add(s)) out.add(Pair(s, 0L))
    }
    return out
}

fun parseArgs(args: Array<String>): Cfg {
    var graph = ""
    var rows = 0
    var cols = 0
    var n = 0
    var p = 0.0
    var k = 1
    var B = 0L
    var trials = 1
    var seed = 1L
    var maxw = 100
    var m0 = 5
    var m = 5
    var i = 0
    while (i < args.size) {
        when (args[i]) {
            "--graph" -> { graph = args[i+1]; i += 2 }
            "--rows" -> { rows = args[i+1].toInt(); i += 2 }
            "--cols" -> { cols = args[i+1].toInt(); i += 2 }
            "--n" -> { n = args[i+1].toInt(); i += 2 }
            "--p" -> { p = args[i+1].toDouble(); i += 2 }
            "--k" -> { k = args[i+1].toInt(); i += 2 }
            "--B" -> { B = args[i+1].toLong(); i += 2 }
            "--trials" -> { trials = args[i+1].toInt(); i += 2 }
            "--seed" -> { seed = args[i+1].toLong(); i += 2 }
            "--maxw" -> { maxw = args[i+1].toInt(); i += 2 }
            "--m0" -> { m0 = args[i+1].toInt(); i += 2 }
            "--m" -> { m = args[i+1].toInt(); i += 2 }
            "--json" -> { i += 1 } // ignored flag for compatibility
            else -> { i += 1 }
        }
    }
    return Cfg(graph, rows, cols, n, p, m0, m, k, B, trials, seed, maxw)
}

fun jsonLine(
    impl: String, lang: String, graph: String, n: Int, m: Int, k: Int, B: Long, seed: Long, timeNs: Long,
    popped: Int, scanned: Long, pushes: Long, bprime: Long, memBytes: Long
): String {
    return "{" +
        "\"impl\":\"$impl\"," +
        "\"lang\":\"$lang\"," +
        "\"graph\":\"$graph\"," +
        "\"n\":$n," +
        "\"m\":$m," +
        "\"k\":$k," +
        "\"B\":$B," +
        "\"seed\":$seed," +
        "\"time_ns\":$timeNs," +
        "\"popped\":$popped," +
        "\"edges_scanned\":$scanned," +
        "\"heap_pushes\":$pushes," +
        "\"B_prime\":$bprime," +
        "\"mem_bytes\":$memBytes" +
        "}"
}

fun main(args: Array<String>) {
    val cfg = parseArgs(args)
    for (t in 0 until cfg.trials) {
        val rng = Random(cfg.seed + t)
        val g = when (cfg.graph) {
            "grid" -> makeGrid(cfg.rows, cfg.cols, rng, cfg.maxw)
            "er" -> makeER(cfg.n, cfg.p, rng, cfg.maxw)
            "ba" -> makeBA(cfg.n, cfg.m0, cfg.m, rng, cfg.maxw)
            else -> return
        }
        val sources = pickSources(g.n, cfg.k, rng)
        val t0 = System.nanoTime()
        val res = bmssp(g, sources, cfg.B)
        val t1 = System.nanoTime()
        val timeNs = t1 - t0
        val memBytes = (g.m().toLong() * 16L) + (g.n.toLong() * 16L)
        val line = jsonLine(
            impl = "kotlin-bmssp", lang = "Kotlin", graph = cfg.graph,
            n = g.n, m = g.m(), k = cfg.k, B = cfg.B, seed = cfg.seed + t,
            timeNs = timeNs, popped = res.explored, scanned = res.edgesScanned,
            pushes = res.heapPushes, bprime = if (res.bPrime == Long.MAX_VALUE) cfg.B else res.bPrime,
            memBytes = memBytes
        )
        println(line)
    }
}
