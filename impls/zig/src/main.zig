const std = @import("std");
const Allocator = std.mem.Allocator;

const Entry = struct { d: u64, v: u32 };

fn lessThan(a: Entry, b: Entry) bool { return a.d < b.d or (a.d == b.d and a.v < b.v); }

const Edge = struct { to: u32, w: u64 };
const Graph = struct {
    n: u32,
    head: []u32,
    edges: []Edge,
};

fn makeGrid(alloc: Allocator, rows: u32, cols: u32, maxw: u32, seed: u64) !Graph {
    var prng = std.Random.DefaultPrng.init(seed);
    const rnd = prng.random();
    const n: u32 = rows * cols;
    var buckets = try alloc.alloc(std.ArrayList(Edge), n);
    var i: u32 = 0; while (i < n) : (i += 1) { buckets[i] = std.ArrayList(Edge).init(alloc); }
    var r: u32 = 0;
    while (r < rows) : (r += 1) {
        var c: u32 = 0;
        while (c < cols) : (c += 1) {
            const u: u32 = r * cols + c;
            if (r + 1 < rows) {
                const v: u32 = (r + 1) * cols + c;
                const w = @as(u64, @intCast(rnd.intRangeAtMost(u32, 1, maxw)));
                try buckets[u].append(.{ .to = v, .w = w });
                try buckets[v].append(.{ .to = u, .w = w });
            }
            if (c + 1 < cols) {
                const v2: u32 = r * cols + (c + 1);
                const w2 = @as(u64, @intCast(rnd.intRangeAtMost(u32, 1, maxw)));
                try buckets[u].append(.{ .to = v2, .w = w2 });
                try buckets[v2].append(.{ .to = u, .w = w2 });
            }
        }
    }
    const g = try finalizeFromBuckets(alloc, n, buckets);
    i = 0; while (i < n) : (i += 1) { buckets[i].deinit(); }
    alloc.free(buckets);
    return g;
}

fn finalizeFromBuckets(alloc: Allocator, n: u32, buckets: []std.ArrayList(Edge)) !Graph {
    var head = try alloc.alloc(u32, n + 1);
    var total: usize = 0;
    head[0] = 0;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        total += buckets[i].items.len;
    head[@as(usize, @intCast(i + 1))] = @as(u32, @truncate(total));
    }
    var edges = try alloc.alloc(Edge, total);
    i = 0;
    var off: usize = 0;
    while (i < n) : (i += 1) {
        const blen = buckets[i].items.len;
        std.mem.copyForwards(Edge, edges[off .. off + blen], buckets[i].items);
        off += blen;
    }
    return Graph{ .n = n, .head = head, .edges = edges };
}

// makeER defined below

// makeBA defined below

// ER and BA generators
fn makeER(alloc: Allocator, n: u32, p: f64, maxw: u32, seed: u64) !Graph {
    var prng = std.Random.DefaultPrng.init(seed);
    const rnd = prng.random();
    var buckets = try alloc.alloc(std.ArrayList(Edge), n);
    var i: u32 = 0; while (i < n) : (i += 1) { buckets[i] = std.ArrayList(Edge).init(alloc); }
    i = 0;
    while (i + 1 < n) : (i += 1) {
        var j: u32 = i + 1;
        while (j < n) : (j += 1) {
            if (rnd.float(f64) < p) {
                const w = @as(u64, @intCast(rnd.intRangeAtMost(u32, 1, maxw)));
                try buckets[i].append(.{ .to = j, .w = w });
                try buckets[j].append(.{ .to = i, .w = w });
            }
        }
    }
    const g = try finalizeFromBuckets(alloc, n, buckets);
    i = 0; while (i < n) : (i += 1) { buckets[i].deinit(); }
    alloc.free(buckets);
    return g;
}

fn makeBA(alloc: Allocator, n: u32, m0: u32, m: u32, maxw: u32, seed: u64) !Graph {
    var prng = std.Random.DefaultPrng.init(seed);
    const rnd = prng.random();
    var buckets = try alloc.alloc(std.ArrayList(Edge), n);
    var i: u32 = 0; while (i < n) : (i += 1) { buckets[i] = std.ArrayList(Edge).init(alloc); }
    var deg_list = std.ArrayList(u32).init(alloc);
    defer deg_list.deinit();
    var deg = try alloc.alloc(u32, n);
    defer alloc.free(deg);
    @memset(deg, 0);

    const clique: u32 = if (m0 < 2) 2 else m0;
    i = 0;
    while (i + 1 < clique) : (i += 1) {
        var j: u32 = i + 1;
        while (j < clique) : (j += 1) {
            const w = @as(u64, @intCast(rnd.intRangeAtMost(u32, 1, maxw)));
            try buckets[i].append(.{ .to = j, .w = w });
            try buckets[j].append(.{ .to = i, .w = w });
            deg[i] += 1; deg[j] += 1;
            try deg_list.append(i);
            try deg_list.append(j);
        }
    }

    var v: u32 = clique;
    while (v < n) : (v += 1) {
        var chosen = std.AutoHashMap(u32, void).init(alloc);
        defer chosen.deinit();
        var added: u32 = 0;
        if (deg_list.items.len == 0) {
            var u: u32 = 0;
            while (u < @min(m, v)) : (u += 1) {
                if (u == v) continue;
                const w = @as(u64, @intCast(rnd.intRangeAtMost(u32, 1, maxw)));
                try buckets[v].append(.{ .to = u, .w = w });
                try buckets[u].append(.{ .to = v, .w = w });
                deg[v] += 1; deg[u] += 1;
                try deg_list.append(v);
                try deg_list.append(u);
                added += 1;
                if (added == m) break;
            }
        } else {
            while (added < m) {
                const idx = rnd.intRangeAtMost(usize, 0, deg_list.items.len - 1);
                const u = deg_list.items[idx];
                if (u == v) continue;
                if (chosen.get(u) != null) continue;
                try chosen.put(u, {});
                const w = @as(u64, @intCast(rnd.intRangeAtMost(u32, 1, maxw)));
                try buckets[v].append(.{ .to = u, .w = w });
                try buckets[u].append(.{ .to = v, .w = w });
                deg[v] += 1; deg[u] += 1;
                try deg_list.append(v);
                try deg_list.append(u);
                added += 1;
            }
        }
    }

    const g = try finalizeFromBuckets(alloc, n, buckets);
    i = 0; while (i < n) : (i += 1) { buckets[i].deinit(); }
    alloc.free(buckets);
    return g;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    const alloc = gpa.allocator();

    var graph: []const u8 = "grid";
    var rows: u32 = 50; var cols: u32 = 50; var k: u32 = 16; var maxw: u32 = 100; var B: u64 = 200; var seed: u64 = 42; var trials: u32 = 5;
    var n_er: u32 = 1000; var p_er: f64 = 0.01;
    var n_ba: u32 = 1000; var m0_ba: u32 = 5; var m_ba: u32 = 5;

    var it = try std.process.argsWithAllocator(alloc);
    defer it.deinit();
    _ = it.next(); // skip prog
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--graph")) graph = it.next().?
        // Zig implementation removed
        else if (std.mem.eql(u8, arg, "--cols")) cols = try std.fmt.parseInt(u32, it.next().?, 10)
