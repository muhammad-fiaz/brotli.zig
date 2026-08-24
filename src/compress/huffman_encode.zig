//! Native Huffman tree construction and serialization for the encoder.
//!
//! Produces RFC 7932 section 3.5 trees: simple trees for up to four used
//! symbols, complex code-length-coded trees otherwise. Code lengths are
//! generated from symbol frequencies and limited to fifteen bits.

const std = @import("std");
const prefix = @import("../decompress/prefix.zig");

pub const MAX_CODE_LENGTH = 15;

/// LSB-first bit sink over a preallocated buffer.
pub const BitSink = struct {
    buf: []u8,
    pos: usize = 0,

    pub inline fn put(self: *BitSink, n_bits: u6, value: u64) void {
        std.debug.assert(value >> n_bits == 0);
        const p = self.buf[self.pos >> 3 ..];
        const v = std.mem.readInt(u64, p[0..8], .little);
        std.mem.writeInt(u64, p[0..8], v | (value << @intCast(self.pos & 7)), .little);
        self.pos += n_bits;
    }

    pub inline fn putBits(self: *BitSink, n_bits: u5, value: u64) void {
        if (n_bits == 0) return;
        self.put(@intCast(n_bits), value);
    }

    /// Zero-padding to the next byte boundary.
    pub fn alignToByte(self: *BitSink) void {
        self.pos = (self.pos + 7) & ~@as(usize, 7);
    }
};

fn log2Floor(x: u64) u6 {
    if (x == 0) return 0;
    return std.math.log2_int(u64, x);
}

/// Width in bits used to store one raw symbol of an alphabet of size
/// `alphabet_size_max` (mirrors the decoder's simple-tree symbol width).
pub fn alphabetBits(alphabet_size_max: u32) u6 {
    if (alphabet_size_max <= 1) return 1;
    return @as(u6, log2Floor(alphabet_size_max - 1)) + 1;
}

const EMPTY: u16 = 0xFFFF;
const UNDEF: usize = 0xFFFF_FFFF;
const MAX_ALPHABET = 704;

/// Assigns Huffman code lengths (<= max_depth) to nonzero frequencies.
/// `depths` is fully overwritten; zero-frequency symbols get depth 0.
pub fn generateCodeLengths(freqs: []const u32, max_depth: u8, depths: []u8) void {
    const n = freqs.len;
    std.debug.assert(depths.len >= n);
    @memset(depths[0..n], 0);

    var used: usize = 0;
    for (freqs) |f| {
        if (f != 0) used += 1;
    }
    if (used == 0) return;
    if (used == 1) return; // zero-bit code for the lone symbol

    // O(n^2) two-queue Huffman construction; alphabets are tiny (<=704).
    var weight: [2 * MAX_ALPHABET]u64 = undefined;
    var child_l: [2 * MAX_ALPHABET]u16 = undefined;
    var child_r: [2 * MAX_ALPHABET]u16 = undefined;
    var alive: [2 * MAX_ALPHABET]bool = undefined;
    var leaf_of: [MAX_ALPHABET]u16 = undefined;
    var count: usize = 0;
    for (freqs[0..n], 0..) |f, sym| {
        if (f == 0) continue;
        weight[count] = f;
        child_l[count] = EMPTY;
        child_r[count] = EMPTY;
        alive[count] = true;
        leaf_of[sym] = @intCast(count);
        count += 1;
    }

    while (true) {
        var a: usize = UNDEF;
        var b: usize = UNDEF;
        for (0..count) |i| {
            if (!alive[i]) continue;
            if (a == UNDEF or weight[i] < weight[a]) {
                b = a;
                a = i;
            } else if (b == UNDEF or weight[i] < weight[b]) {
                b = i;
            }
        }
        if (b == UNDEF) break; // root remains
        weight[count] = weight[a] + weight[b];
        child_l[count] = @intCast(a);
        child_r[count] = @intCast(b);
        alive[a] = false;
        alive[b] = false;
        alive[count] = true;
        count += 1;
    }

    // Depth of every node via iterative descent from the root.
    var depth_of: [2 * MAX_ALPHABET]u8 = undefined;
    const root = count - 1;
    depth_of[root] = 0;
    var stack: [64]usize = undefined;
    var sp: usize = 0;
    stack[sp] = root;
    sp += 1;
    while (sp != 0) {
        sp -= 1;
        const node = stack[sp];
        const d = depth_of[node];
        if (child_l[node] != EMPTY) {
            depth_of[child_l[node]] = d + 1;
            depth_of[child_r[node]] = d + 1;
            stack[sp] = child_l[node];
            sp += 1;
            stack[sp] = child_r[node];
            sp += 1;
        }
    }
    for (depths[0..n], 0..) |*d, sym| {
        if (freqs[sym] != 0) d.* = depth_of[leaf_of[sym]];
    }

    var deepest: u8 = 0;
    for (depths[0..n]) |d| {
        if (d > deepest) deepest = d;
    }
    if (deepest <= max_depth) return; // already complete within the cap

    // Fallback for skewed distributions: start from the minimal complete
    // uniform tree covering all used symbols, then improve by
    // cost-decreasing exchanges. Every intermediate state keeps the same
    // length multiset, so the result is always a valid complete code.
    exchangeLengths(freqs[0..n], max_depth, depths[0..n]);
}

fn exchangeLengths(freqs: []const u32, max_depth: u8, depths: []u8) void {
    _ = max_depth;
    var order: [MAX_ALPHABET]u16 = undefined;
    var m: usize = 0;
    for (freqs, 0..) |f, s| {
        if (f != 0) {
            order[m] = @intCast(s);
            m += 1;
        }
    }
    const SortCtx = struct {
        freqs: []const u32,
        pub fn lessThan(ctx: @This(), a: u16, b: u16) bool {
            return ctx.freqs[a] > ctx.freqs[b];
        }
    };
    std.mem.sort(u16, order[0..m], SortCtx{ .freqs = freqs }, SortCtx.lessThan);

    var k: u6 = 0;
    while ((@as(usize, 1) << k) < m) k += 1;
    // k = ceil(log2(m)); complete tree: x leaves at depth k-1, y at depth k.
    const kk: usize = k;
    const x: usize = (@as(usize, 1) << @intCast(kk)) - m;

    for (order[0..m], 0..) |s, i| {
        depths[s] = if (i < x)
            @intCast(kk -| 1)
        else
            @intCast(kk);
    }

    // Swapping lengths between a deeper higher-frequency leaf and a shallower
    // lower-frequency leaf preserves completeness and strictly reduces cost.
    var changed = true;
    while (changed) {
        changed = false;
        for (order[0..m]) |a| {
            for (order[0..m]) |b| {
                const da = depths[a];
                const db = depths[b];
                if (da > db and freqs[a] > freqs[b]) {
                    depths[a] = db;
                    depths[b] = da;
                    changed = true;
                }
            }
        }
    }
}

fn kraftSum(depths: []const u8, max_depth: u8) u64 {
    var sum: u64 = 0;
    for (depths) |d| {
        if (d != 0) sum += @as(u64, 1) << @intCast(max_depth - d);
    }
    return sum;
}

/// Canonical code assignment per RFC 7932 section 3.2, converted to
/// transmission order: the bit sink emits LSB-first while prefix codes are
/// matched most-significant-bit first, so stored codes are bit-reversed.
pub fn assignCanonicalCodes(depths: []const u8, codes: []u16) void {
    var next: [MAX_CODE_LENGTH + 2]u32 = undefined;
    var code: u32 = 0;
    var l: usize = 1;
    while (l <= MAX_CODE_LENGTH) : (l += 1) {
        next[l] = code;
        var cnt: u32 = 0;
        for (depths) |d| {
            if (d == l) cnt += 1;
        }
        code = (code + cnt) << 1;
    }
    for (depths, 0..) |d, sym| {
        if (d == 0) {
            codes[sym] = 0;
        } else {
            const canonical: u16 = @intCast(next[d]);
            codes[sym] = reverseN(canonical, @intCast(d));
            next[d] += 1;
        }
    }
}

/// Reverses the low `n` bits of `v`.
fn reverseN(v: u16, n: u5) u16 {
    var r: u16 = 0;
    var i: u4 = 0;
    while (i < n) : (i += 1) {
        const bit: u16 = (v >> i) & 1;
        r |= bit << @intCast(n - 1 - i);
    }
    return r;
}

fn emitClLength(w: *BitSink, len: u8) void {
    // Fixed variable-length codes for code-length values 0..5 (RFC 3.5).
    switch (len) {
        0 => w.put(2, 0),
        4 => w.put(2, 1),
        3 => w.put(2, 2),
        1 => w.put(4, 7),
        2 => w.put(3, 3),
        5 => w.put(4, 15),
        else => unreachable,
    }
}

/// Serializes one prefix tree into `w`; fills `depths`/`codes` (sized >= limit)
/// for subsequent symbol emission. `cl_depths` must hold >= 18 entries.
pub fn storeHuffmanTree(
    w: *BitSink,
    freqs: []const u32,
    alphabet_size_max: u32,
    alphabet_size_limit: u32,
    depths: []u8,
    codes: []u16,
    cl_depths: []u8,
) void {
    const limit: usize = alphabet_size_limit;
    generateCodeLengths(freqs, MAX_CODE_LENGTH, depths[0..limit]);

    var syms: [MAX_ALPHABET]u16 = undefined;
    var nsyms: usize = 0;
    for (0..limit) |s| {
        if (freqs[s] != 0) {
            syms[nsyms] = @intCast(s);
            nsyms += 1;
        }
    }

    const width = alphabetBits(alphabet_size_max);

    if (nsyms == 0) {
        depths[0] = 0;
        codes[0] = 0;
        w.put(2, 1); // simple marker
        w.put(2, 0); // NSYM-1
        w.putBits(@intCast(width), 0);
        return;
    }

    if (nsyms <= 4) {
        w.put(2, 1); // simple marker
        w.put(2, @intCast(nsyms - 1));
        switch (nsyms) {
            1 => depths[syms[0]] = 0,
            2 => {
                depths[syms[0]] = 1;
                depths[syms[1]] = 1;
            },
            3 => {
                // Matches the decoder's three-symbol layout.
                depths[syms[0]] = 1;
                depths[syms[1]] = 2;
                depths[syms[2]] = 2;
            },
            else => {
                for (syms[0..nsyms]) |s| depths[s] = 2;
            },
        }
        assignCanonicalCodes(depths[0..limit], codes);
        for (syms[0..nsyms]) |s| w.putBits(@intCast(width), s);
        if (nsyms == 4) w.put(1, 0); // tree-select: uniform depths
        return;
    }

    // Complex tree with code-length coding.
    w.put(2, 0); // HSKIP = 0

    var cl_freqs = [_]u32{0} ** 18;
    // Detect the degenerate "every used symbol has the same nonzero depth"
    // case: its CL histogram would contain a single symbol, which the nested
    // tree cannot express. Splitting off one direct emission guarantees at
    // least two distinct CL symbols.
    var min_d: u8 = 255;
    var max_d: u8 = 0;
    for (depths[0..limit]) |d| {
        if (d == 0) continue;
        if (d < min_d) min_d = d;
        if (d > max_d) max_d = d;
    }
    const force_split = min_d != 255 and min_d == max_d;
    histogramDepths(depths[0..limit], &cl_freqs, force_split);

    // Degenerate case: exactly ONE distinct CL symbol (all lengths equal).
    // The nested tree then carries a single nominal entry; the decoder's
    // single-code table answers every lookup with that length at zero bits.
    var used_cl: usize = 0;
    var only_sym: u8 = 0;
    for (cl_freqs, 0..) |f, s| {
        if (f != 0) {
            used_cl += 1;
            only_sym = @intCast(s);
        }
    }
    if (used_cl == 1) {
        @memset(cl_depths[0..18], 0);
        cl_depths[only_sym] = 1;
        var idx2: usize = 0;
        var spc: u32 = 32;
        while (idx2 < 18) : (idx2 += 1) {
            const sym2 = prefix.code_length_prefix_order[idx2];
            emitClLength(w, cl_depths[sym2]);
            if (cl_depths[sym2] != 0) {
                spc = spc -% (@as(u32, 32) >> @intCast(cl_depths[sym2]));
                if (spc == 0 or spc > 32) break;
            }
        }
        // Zero-width emission context: every lookup yields `only_sym`.
        var z_depths = [_]u8{0} ** 18;
        z_depths[only_sym] = 0;
        const z_codes = [_]u16{0} ** 18;
        const ctx = ClContext{ .codes = z_codes, .depths = z_depths };
        emitDepthSymbols(w, depths[0..limit], &ctx, false);
        assignCanonicalCodes(depths[0..limit], codes);
        return;
    }

    generateCodeLengths(&cl_freqs, 5, cl_depths[0..18]);
    var cl_codes: [18]u16 = undefined;
    assignCanonicalCodes(cl_depths[0..18], &cl_codes);

    // Fill the caller-visible code tables for later symbol emission.
    assignCanonicalCodes(depths[0..limit], codes);

    // Emit the nested CL tree in the decoder's reordered symbol sequence,
    // stopping exactly when the Kraft space is exhausted (mirrors decode).
    var space: u32 = 32;
    var nonzeros: usize = 0;
    var i: usize = 0;
    while (i < 18) : (i += 1) {
        const sym = prefix.code_length_prefix_order[i];
        emitClLength(w, cl_depths[sym]);
        if (cl_depths[sym] != 0) {
            space = space -% (@as(u32, 32) >> @intCast(cl_depths[sym]));
            nonzeros += 1;
            if (space == 0 or space > 32) break;
        }
    }
    std.debug.assert(nonzeros >= 2 or nonzeros == 1);

    const ctx = ClContext{ .codes = cl_codes, .depths = cl_depths[0..18].* };
    emitDepthSymbols(w, depths[0..limit], &ctx, force_split);
}

/// Counts CL symbols produced by the exact scheme `emitDepthSymbols` uses.
/// Repeat codes are never emitted adjacently: the decoder's repeat counter
/// accumulates across consecutive repeats ((r-2)*4 + e + 3), so pairing each
/// repeat with an intervening direct symbol keeps coverage exact.
fn histogramDepths(depths: []const u8, cl_freqs: *[18]u32, force_split: bool) void {
    var space: u32 = 1 << MAX_CODE_LENGTH;
    var start: usize = 0;
    if (force_split and depths.len != 0 and depths[0] != 0) {
        cl_freqs[depths[0]] += 1;
        space -%= @as(u32, 1) << @intCast(MAX_CODE_LENGTH - depths[0]);
        start = 1;
    }
    var i = start;
    while (i < depths.len and space != 0) : (i += 1) {
        const d = depths[i];
        if (d == 0) {
            cl_freqs[0] += 1;
            continue;
        }
        cl_freqs[d] += 1;
        space -%= @as(u32, 1) << @intCast(MAX_CODE_LENGTH - d);
    }
}
fn emitClSymbol(w: *BitSink, sym: u8, ctx: *const ClContext) void {
    const d = ctx.depths[sym];
    if (d != 0) w.putBits(@intCast(d), ctx.codes[sym]);
}

pub const ClContext = struct {
    codes: [18]u16,
    depths: [18]u8,
};

/// Emits per-symbol code lengths directly (no repeat codes), stopping
/// exactly when the Kraft sum saturates. Mirrors `histogramDepths`.
fn emitDepthSymbols(w: *BitSink, depths: []const u8, ctx: *const ClContext, force_split: bool) void {
    var space: u32 = 1 << MAX_CODE_LENGTH;
    var start: usize = 0;
    if (force_split and depths.len != 0 and depths[0] != 0) {
        emitClSymbol(w, depths[0], ctx);
        space -%= @as(u32, 1) << @intCast(MAX_CODE_LENGTH - depths[0]);
        start = 1;
    }
    var i = start;
    while (i < depths.len and space != 0) : (i += 1) {
        const d = depths[i];
        if (d == 0) {
            emitClSymbol(w, 0, ctx);
            continue;
        }
        emitClSymbol(w, d, ctx);
        space -%= @as(u32, 1) << @intCast(MAX_CODE_LENGTH - d);
    }
}
