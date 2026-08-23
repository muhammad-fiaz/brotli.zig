//! Native greedy/lazy LZ77 backward-reference matcher.
//!
//! Hash-chain matcher over a contiguous buffer that begins with the retained
//! history of previously emitted blocks; produced commands mirror the decoder
//! ring-buffer semantics exactly.

const std = @import("std");

pub const MIN_MATCH = 4;
pub const MAX_MATCH = 16779;

pub const Command = struct {
    insert_len: u32,
    copy_len: u32,
    /// Absolute distance (1 = previous byte).
    dist: u32 = 0,
};

/// Recent-distance cache mirroring the decoder state.
pub const DistRb = struct {
    rb: [4]u32 = .{ 16, 15, 11, 4 },
    idx: i32 = 0,

    pub fn last(self: *const DistRb) u32 {
        return self.rb[@intCast((self.idx -% 1) & 3)];
    }

    pub fn push(self: *DistRb, d: u32) void {
        self.rb[@intCast(self.idx & 3)] = d;
        self.idx +%= 1;
    }
};

pub const Params = struct {
    max_chain: u32 = 16,
    lazy: bool = true,
    min_match: usize = MIN_MATCH,
};

const HASH_BITS = 17;
const HASH_SIZE = 1 << HASH_BITS;

fn hash4(buf: []const u8, pos: usize) u32 {
    const v = std.mem.readInt(u32, buf[pos..][0..4], .little);
    return (v *% 0x1E35A7BD) >> @intCast(32 - HASH_BITS);
}

pub const MatchResult = struct {
    len: usize,
    dist: u32,
};

fn findMatch(
    buf: []const u8,
    pos: usize,
    max_dist: usize,
    head: []const i64,
    prev: []const i64,
    params: Params,
    best_floor: usize,
) ?MatchResult {
    if (pos + params.min_match > buf.len) return null;
    const h = hash4(buf, pos);
    var cand = head[h];
    var best_len = best_floor;
    var best_dist: u32 = 0;
    const limit = @min(max_dist, pos);
    var chain: u32 = 0;
    while (cand >= 0) : (chain += 1) {
        const c: usize = @intCast(cand);
        if (c == pos or c >= pos) break; // self-reference guard
        const dist = pos - c;
        if (dist > limit) break;
        if (best_len >= 8 and pos + best_len < buf.len and
            buf[c + best_len] != buf[pos + best_len])
        {
            cand = prev[c];
            chain += 1;
            if (chain >= params.max_chain) break;
            continue;
        }
        var l: usize = 0;
        const cap = @min(buf.len - pos, MAX_MATCH);
        while (l < cap and buf[c + l] == buf[pos + l]) l += 1;
        if (l > best_len) {
            best_len = l;
            best_dist = @intCast(dist);
            if (l >= MAX_MATCH) break;
        }
        if (chain >= params.max_chain) break;
        cand = prev[c];
    }
    if (best_len < params.min_match or best_dist == 0) return null;
    return .{ .len = best_len, .dist = best_dist };
}

fn insertHash(head: []i64, prev: []i64, buf: []const u8, pos: usize) void {
    if (prev[pos] != -1) return; // already chained
    const h = hash4(buf, pos);
    prev[pos] = head[h];
    head[h] = @intCast(pos);
}

/// Runs the matcher over `buf[start..]`, appending commands to `out`.
/// Trailing literals form a final copy-less command.
pub fn compress(
    allocator: std.mem.Allocator,
    buf: []const u8,
    start: usize,
    end: usize,
    max_dist: usize,
    params: Params,
    out: *std.ArrayList(Command),
) !void {
    const head = try allocator.alloc(i64, HASH_SIZE);
    @memset(head, -1);
    defer allocator.free(head);
    const prev = try allocator.alloc(i64, buf.len);
    @memset(prev, -1);
    defer allocator.free(prev);

    // Pre-hash history (custom dictionary and/or prior blocks) so output
    // positions can form back-references into it.
    {
        var h: usize = 0;
        while (h + params.min_match <= start) : (h += 1) {
            insertHash(head, prev, buf, h);
        }
    }

    var pos = start;
    var lit_start = start;

    while (pos < end) {
        if (pos + params.min_match > end) break;

        const m = findMatch(buf, pos, max_dist, head, prev, params, params.min_match - 1);

        if (params.lazy and m != null) {
            // One-step lazy evaluation: prefer a longer match that starts
            // one byte later. The current position's hash is recorded either
            // way; when deferring, the next iteration picks up the better
            // match on its own.
            insertHash(head, prev, buf, pos);
            if (pos + 1 + params.min_match <= end) {
                if (findMatch(buf, pos + 1, max_dist, head, prev, params, m.?.len)) |m2| {
                    if (m2.len > m.?.len) {
                        pos += 1;
                        continue;
                    }
                }
            }
        }

        if (m == null) {
            insertHash(head, prev, buf, pos);
            pos += 1;
            continue;
        }

        const match = m.?;
        var ip = pos;
        const stop = pos + match.len;
        while (ip < stop) : (ip += 1) {
            if (ip + params.min_match <= end) insertHash(head, prev, buf, ip);
        }
        try out.append(allocator, .{
            .insert_len = @intCast(pos - lit_start),
            .copy_len = @intCast(match.len),
            .dist = match.dist,
        });
        pos = stop;
        lit_start = stop;
    }

    if (lit_start < end) {
        try out.append(allocator, .{
            .insert_len = @intCast(end - lit_start),
            .copy_len = 0,
            .dist = 0,
        });
    }
}
