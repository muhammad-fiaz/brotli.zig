//! Native Brotli encoder state machine.
//!
//! One-shot and streaming compression producing RFC 7932 streams: window
//! header, compressed metablocks (three single-tree prefix codes, LZ77
//! backward references with recent-distance shortcuts) and stored metablocks
//! for incompressible regions.

const std = @import("std");
const huff_enc = @import("huffman_encode.zig");
const lz77 = @import("lz77.zig");
const prefix = @import("../decompress/prefix.zig");
const constants = @import("../common/constants.zig");
const context = @import("../common/context.zig");
const dictionary = @import("../dictionary/dictionary.zig");
const static_dict = @import("static_dict.zig");
const prefix_ranges = @import("../common/prefix_ranges.zig");

pub const Mode = enum(u3) {
    generic = 0,
    text = 1,
    font = 2,

    pub fn fromInt(v: u32) Mode {
        return switch (v & 3) {
            1 => .text,
            2 => .font,
            else => .generic,
        };
    }
};

pub const Operation = enum(u8) {
    process = 0,
    flush = 1,
    finish = 2,
    /// The input slice carries a metadata payload (see RFC 7932 section 9.2).
    emit_metadata = 3,
};

/// Optional progress observer fired while large inputs are compressed.
pub const ProgressCallback = *const fn (
    ctx: ?*anyopaque,
    bytes_done: usize,
    bytes_total: usize,
) void;

pub const Options = struct {
    quality: u32 = 11,
    lgWin: u32 = 22,
    mode: Mode = .generic,
    lgBlock: u32 = 0,
    disableLiteralContextModeling: bool = false,
    sizeHint: usize = 0,
    largeWindow: bool = false,
    nPostfix: u32 = 0,
    nDirect: u32 = 0,
    customDictionary: ?[]const u8 = null,
    progress: ?ProgressCallback = null,
    progressCtx: ?*anyopaque = null,
};

/// Parameter identifiers, mirroring the C enumeration values.
pub const paramMode: u32 = 0;
pub const paramQuality: u32 = 1;
pub const paramLgWin: u32 = 2;
pub const paramLgBlock: u32 = 3;
pub const paramDisableLiteralContextModeling: u32 = 4;
pub const paramSizeHint: u32 = 5;
pub const paramLargeWindow: u32 = 6;
pub const paramNPostfix: u32 = 7;
pub const paramNDirect: u32 = 8;

const MAX_MLEN = 1 << 24;
const WINDOW_GAP = 16;
const MIN_WINDOW = 10;
const MAX_WINDOW = 24;
const LARGE_MAX_WINDOW = constants.LARGE_MAX_WBITS;
/// Widest possible distance alphabet across every supported configuration.
const DIST_ALPHABET_MAX = 544;

fn effectiveWindow(opts: Options) u32 {
    var w = opts.lgWin;
    if (w < MIN_WINDOW) w = MIN_WINDOW;
    const cap: u32 = if (opts.largeWindow) LARGE_MAX_WINDOW else MAX_WINDOW;
    if (w > cap) w = cap;
    return w;
}

/// Normalizes nPostfix/nDirect the way the format requires: the four-bit
/// header field carries nDirect >> nPostfix, so nDirect stays within
/// 15 << nPostfix and is a multiple of the postfix multiplier.
fn sanitizeDistanceParams(opts: *Options) void {
    if (opts.nPostfix > constants.MAX_NPOSTFIX) opts.nPostfix = constants.MAX_NPOSTFIX;
    const mult = @as(u32, 1) << @intCast(opts.nPostfix);
    const max_nd = @as(u32, 15) * mult;
    var nd = opts.nDirect;
    if (nd > max_nd) nd = max_nd;
    if (opts.nDirect > constants.MAX_NDIRECT) opts.nDirect = constants.MAX_NDIRECT;
    nd -= nd % mult;
    opts.nDirect = nd;
}

fn qualityParams(q: u32) lz77.Params {
    if (q <= 1) return .{ .max_chain = 1, .lazy = false };
    if (q <= 3) return .{ .max_chain = 8, .lazy = false };
    if (q <= 6) return .{ .max_chain = 16, .lazy = true };
    if (q <= 9) return .{ .max_chain = 32, .lazy = true };
    return .{ .max_chain = 64, .lazy = true };
}

const kInsEb = [24]u8{
    0, 0, 0, 0, 0, 0, 1, 1, 2,  2,  3,  3,
    4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 14, 24,
};
const kCopyEb = [24]u8{
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2,  2,
    3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 24,
};

const ins_off: [24]u32 = blk: {
    @setEvalBranchQuota(10000);
    var off: [24]u32 = undefined;
    off[0] = 0;
    for (0..23) |i| off[i + 1] = off[i] + (@as(u32, 1) << @intCast(kInsEb[i]));
    break :blk off;
};
const copy_off: [24]u32 = blk: {
    @setEvalBranchQuota(10000);
    var off: [24]u32 = undefined;
    off[0] = 2;
    for (0..23) |i| off[i + 1] = off[i] + (@as(u32, 1) << @intCast(kCopyEb[i]));
    break :blk off;
};

fn findCode(off: *const [24]u32, target: u32) u8 {
    for (off, 0..) |o, i| {
        if (o == target) return @intCast(i);
    }
    unreachable;
}

fn codeFor(off: *const [24]u32, value: u32) struct { code: u8, extra: u32 } {
    var i: usize = 23;
    while (i > 0) : (i -= 1) {
        if (value >= off[i]) return .{ .code = @intCast(i), .extra = value - off[i] };
    }
    return .{ .code = 0, .extra = value - off[0] };
}

const CmdMaps = struct {
    explicit_sym: [24][24]u16,
    implicit_sym: [24][24]u16,

    fn init() CmdMaps {
        @setEvalBranchQuota(400000);
        var m: CmdMaps = undefined;
        for (&m.explicit_sym) |*row| @memset(row, 0xFFFF);
        for (&m.implicit_sym) |*row| @memset(row, 0xFFFF);
        for (prefix.cmd_lut, 0..) |e, sym| {
            const ic = findCode(&ins_off, e.insert_len_offset);
            const jc = findCode(&copy_off, e.copy_len_offset);
            if (e.distance_code < 0) {
                m.explicit_sym[ic][jc] = @intCast(sym);
            } else {
                m.implicit_sym[ic][jc] = @intCast(sym);
            }
        }
        return m;
    }
};

const cmd_maps = CmdMaps.init();

/// Encodes a copy distance (already offset by the short-code window) into a
/// distance symbol plus extra bits, mirroring the decoder's LUT exactly.
/// `d` is the raw distance (1-based); returns null when it exceeds the
/// representable range for the active configuration.
fn encodeCopyDistance(
    d: u32,
    ndirect: u32,
    npostfix: u32,
) ?struct { sym: u32, extra: u32, nbits: u5 } {
    if (d == 0) return null;
    const dc = d + constants.NUM_DISTANCE_SHORT_CODES - 1;
    if (dc < constants.NUM_DISTANCE_SHORT_CODES + ndirect) {
        return .{ .sym = dc, .extra = 0, .nbits = 0 };
    }
    const postfix = @as(u32, 1) << @intCast(npostfix);
    const postfix_mask = postfix - 1;
    const dist = (@as(u32, 1) << @intCast(npostfix + 2)) +
        (dc - constants.NUM_DISTANCE_SHORT_CODES - ndirect);
    const bl: u6 = @intCast(std.math.log2_int(u32, dist));
    if (bl == 0) return null;
    const b: u32 = bl - 1;
    if (b < npostfix) return null;
    const pv = dist & postfix_mask;
    const prefix_bit = (dist >> @intCast(b)) & 1;
    const offset = (@as(u32, 2) + prefix_bit) << @intCast(b);
    const nb = b - npostfix;
    const sym = constants.NUM_DISTANCE_SHORT_CODES + ndirect +
        (((2 * (nb - 1) + prefix_bit)) << @intCast(npostfix)) + pv;
    return .{
        .sym = sym,
        .extra = (dist -% offset) >> @intCast(npostfix),
        .nbits = @intCast(nb),
    };
}

/// Extra-bit count for the most recent distance encoding decision.
fn dc_dist_bits(dist: u32) u5 {
    if (dist <= 4) return 0;
    return @intCast(31 - @clz(dist) - 2);
}

const PlanKind = enum { literals_only, implicit_last, explicit_dist };

const PlannedCommand = struct {
    sym: u16,
    insert_len: u32,
    /// Actual output bytes produced by the copy (transformed length for
    /// dictionary references).
    copy_len: u32,
    /// Base length carried in the stream's copy-length code; equals
    /// `copy_len` except for dictionary references.
    copy_code_len: u32,
    ins_extra: u32,
    ins_nbits: u5,
    copy_extra: u32,
    copy_nbits: u5,
    kind: PlanKind,
    dist_code: u16 = 0,
    dist_extra: u32 = 0,
    dist_nbits: u5 = 0,
};

/// Maximum literal trees the context-modeling clusterer will emit.
const MAX_LIT_TREES = 8;
/// Maximum distinct literal block types the splitter may emit.
const MAX_LIT_BLOCK_TYPES = 8;
/// Minimum estimated saving (bits) required to merge two context clusters.
const CLUSTER_MIN_SAVING = 512.0;

/// Literal-context plan for one metablock.
const CtxPlan = struct {
    mode: context.ContextType,
    /// Tree assignment per 64-entry context id.
    cmap: [64]u8 = @splat(0),
    ntrees: u32 = 1,
};

/// A contiguous run of literals within the metablock output.
pub const LitRun = struct { off: u32, len: u32 };

/// Block-length prefix code lookup, mirroring the decoder's range table.
fn blockLengthPrefixCode(len: u32) u8 {
    var code: u8 = if (len >= 177)
        (if (len >= 753) @as(u8, 20) else @as(u8, 14))
    else
        (if (len >= 41) @as(u8, 7) else @as(u8, 0));
    while (code < constants.NUM_BLOCK_LEN_SYMBOLS - 1 and
        len >= prefix_ranges.prefix_code_ranges[code + 1].offset)
    {
        code += 1;
    }
    return code;
}

/// Block-type switch code calculator mirroring the format's ring of the two
/// most recent block types.
const SwitchCalc = struct { last: u32 = 1, second: u32 = 0 };

fn nextBlockTypeCode(calc: *SwitchCalc, t: u32) u16 {
    const code: u16 = if (t == calc.last + 1)
        1
    else if (t == calc.second) 0 else @intCast(t + 2);
    calc.second = calc.last;
    calc.last = t;
    return code;
}

/// Everything needed to emit one category's block-switch machinery.
pub const SwitchTables = struct {
    ntypes: u32,
    /// Borrowed per-literal type ids.
    types_blk: []const u8,
    /// Distinct-type run lengths, ordered.
    types: [MAX_LIT_BLOCK_TYPES]u8 = undefined,
    seg_lens: [MAX_LIT_BLOCK_TYPES]u32 = undefined,
    seg_idx: usize = 1,
    type_freq: [MAX_LIT_BLOCK_TYPES + 2]u32 = @splat(0),
    len_freq: [constants.NUM_BLOCK_LEN_SYMBOLS]u32 = @splat(0),
    type_depths: [MAX_LIT_BLOCK_TYPES + 2]u8 = undefined,
    type_codes: [MAX_LIT_BLOCK_TYPES + 2]u16 = undefined,
    len_depths: [constants.NUM_BLOCK_LEN_SYMBOLS]u8 = undefined,
    len_codes: [constants.NUM_BLOCK_LEN_SYMBOLS]u16 = undefined,

    pub fn finishTables(self: *SwitchTables) void {
        var calc = SwitchCalc{};
        var i: usize = 0;
        while (i < self.ntypes) : (i += 1) {
            const tc = nextBlockTypeCode(&calc, self.types[i]);
            if (i != 0) self.type_freq[tc] += 1;
            self.len_freq[blockLengthPrefixCode(self.seg_lens[i])] += 1;
        }
        huff_enc.generateCodeLengths(&self.type_freq, huff_enc.MAX_CODE_LENGTH, &self.type_depths);
        huff_enc.assignCanonicalCodes(&self.type_depths, &self.type_codes);
        huff_enc.generateCodeLengths(&self.len_freq, huff_enc.MAX_CODE_LENGTH, &self.len_depths);
        huff_enc.assignCanonicalCodes(&self.len_depths, &self.len_codes);
    }
};

/// Plans a literal-block segmentation over the literal stream described by
/// `runs`. Tries equal-count splits, keeps the cheapest by an entropy plus
/// switch-overhead estimate, then greedily merges statistically similar
/// neighbours. Writes one segment id per literal into `seg_of` and returns
/// the segment count (1 when splitting does not pay).
fn planLiteralSegments(
    data: []const u8,
    runs: []const LitRun,
    seg_of: []u8,
) u32 {
    const total: usize = seg_of.len;
    if (total < 1024) {
        @memset(seg_of, 0);
        return 1;
    }
    var best_k: u32 = 1;
    var best_cost: f64 = blk: {
        var all: [256]u32 = @splat(0);
        for (runs) |r| {
            for (data[r.off..][0..r.len]) |b| all[b] += 1;
        }
        break :blk histEntropy(&all);
    };
    const candidates = [_]u32{ 2, 4, 8 };
    for (candidates) |k| {
        var hists: [MAX_LIT_BLOCK_TYPES][256]u32 = @splat(@splat(0));
        var counts: [MAX_LIT_BLOCK_TYPES]usize = @splat(0);
        const per: usize = total / k;
        var li: usize = 0;
        for (runs) |r| {
            for (data[r.off..][0..r.len]) |b| {
                const s = @min(k - 1, @as(u32, @intCast(li / per)));
                hists[s][b] += 1;
                counts[s] += 1;
                li += 1;
            }
        }
        // Total-bit costs on both sides of the comparison.
        var cost: f64 = @as(f64, @floatFromInt(k - 1)) * 16.0 +
            @as(f64, @floatFromInt(k)) * 60.0;
        for (hists[0..k]) |*h| cost += histEntropy(h);
        if (cost + 400.0 < best_cost) {
            best_cost = cost;
            best_k = k;
        }
    }
    if (best_k == 1) {
        @memset(seg_of, 0);
        return 1;
    }
    const per: usize = total / best_k;
    var li: usize = 0;
    for (runs) |r| {
        for (data[r.off..][0..r.len]) |_| {
            seg_of[li] = @intCast(@min(best_k - 1, li / per));
            li += 1;
        }
    }
    // Greedy adjacent merge of statistically similar neighbours.
    var merged: u32 = best_k;
    var s: u32 = 0;
    while (s + 1 < merged) {
        var ha: [256]u32 = @splat(0);
        var hb: [256]u32 = @splat(0);
        var ca: usize = 0;
        var cb: usize = 0;
        var idx: usize = 0;
        for (runs) |r| {
            for (data[r.off..][0..r.len]) |bb| {
                if (seg_of[idx] == s) {
                    ha[bb] += 1;
                    ca += 1;
                } else if (seg_of[idx] == s + 1) {
                    hb[bb] += 1;
                    cb += 1;
                }
                idx += 1;
            }
        }
        if (ca == 0 or cb == 0) break;
        var both = ha;
        for (&both, hb) |*d, sv| d.* += sv;
        const gain = histEntropy(&ha) + histEntropy(&hb) - histEntropy(&both);
        if (gain >= 96.0) {
            for (seg_of) |*sid| {
                if (sid.* > s) sid.* -= 1;
            }
            merged -= 1;
            continue;
        }
        s += 1;
    }
    return merged;
}

fn buildSwitchTables(type_of: []const u8) SwitchTables {
    var st = SwitchTables{ .ntypes = 0, .types_blk = type_of };
    var prev: ?u8 = null;
    for (st.types_blk) |t| {
        if (prev == null or t != prev.?) {
            st.types[st.ntypes] = t;
            st.seg_lens[st.ntypes] = 1;
            st.ntypes += 1;
            prev = t;
        } else {
            st.seg_lens[st.ntypes - 1] += 1;
        }
    }
    st.finishTables();
    return st;
}

pub const Encoder = struct {
    allocator: std.mem.Allocator,
    options: Options,
    window_bits: u32,
    max_backward: usize,
    match_max_dist: usize,

    buf: std.ArrayList(u8) = .empty,
    consumed: usize = 0,

    out: std.ArrayList(u8) = .empty,
    out_pos: usize = 0,

    bitbuf: std.ArrayList(u8) = .empty,
    w: huff_enc.BitSink = .{ .buf = &.{} },

    rb: lz77.DistRb = .{},
    started: bool = false,
    finished_: bool = false,
    failed: bool = false,
    input_total_seen: usize = 0,
    custom_dict: []const u8 = &.{},
    dict_applied: bool = false,
    dict_seeded: bool = false,
    /// Index one past the last custom-dictionary byte in current buffer
    /// coordinates; 0 when no dictionary is in play.
    dict_front_idx: usize = 0,

    /// Sanitized distance-coding parameters.
    npostfix: u32 = 0,
    ndirect: u32 = 0,
    /// Distance alphabet bounds for tree storage (limit) and header
    /// declaration (max); differ only on large-window streams.
    dist_alphabet_limit: u32 = 64,
    dist_alphabet_max: u32 = 64,
    /// Real output bytes already planned/emitted for this stream, excluding
    /// any custom-dictionary seed. Mirrors the decoder's position counter.
    stream_pos: usize = 0,
    /// Last two real output bytes, mirroring decoder P1/P2 state.
    p1: u8 = 0,
    p2: u8 = 0,
    /// Lazily built index over the built-in dictionary; enabled from
    /// quality 4 upward.
    static_lut: ?*static_dict.Lut = null,

    fn refreshDistParams(self: *Encoder) void {
        sanitizeDistanceParams(&self.options);
        self.npostfix = self.options.nPostfix;
        self.ndirect = self.options.nDirect;
        const np = self.npostfix;
        const nd = self.ndirect;
        if (self.options.largeWindow) {
            const lim = constants.calculateDistanceCodeLimit(
                constants.MAX_ALLOWED_DISTANCE,
                np,
                nd,
            );
            self.dist_alphabet_limit = @min(lim.max_alphabet_size, DIST_ALPHABET_MAX);
            self.dist_alphabet_max = @min(
                constants.distanceAlphabetSize(np, nd, constants.LARGE_MAX_DISTANCE_BITS),
                DIST_ALPHABET_MAX,
            );
        } else {
            const sz = constants.distanceAlphabetSize(np, nd, constants.MAX_DISTANCE_BITS);
            self.dist_alphabet_limit = @min(sz, DIST_ALPHABET_MAX);
            self.dist_alphabet_max = self.dist_alphabet_limit;
        }
    }

    pub fn init(allocator: std.mem.Allocator, options: Options) Encoder {
        var opts = options;
        sanitizeDistanceParams(&opts);
        var e = Encoder{
            .allocator = allocator,
            .options = opts,
            .window_bits = effectiveWindow(opts),
            .max_backward = 0,
            .match_max_dist = 0,
        };
        e.max_backward =
            (@as(usize, 1) << @intCast(e.window_bits)) - WINDOW_GAP;
        e.match_max_dist = e.max_backward;
        e.refreshDistParams();
        if (opts.customDictionary) |d| {
            _ = e.attachDictionary(d);
        }
        return e;
    }

    pub fn deinit(self: *Encoder) void {
        self.buf.deinit(self.allocator);
        self.out.deinit(self.allocator);
        self.bitbuf.deinit(self.allocator);
        if (self.static_lut) |l| {
            l.deinit(self.allocator);
            self.allocator.destroy(l);
            self.static_lut = null;
        }
    }

    /// Resets the encoder state for a new stream, reusing allocated buffers and lookup tables.
    pub fn reset(self: *Encoder, options: ?Options) void {
        if (options) |opts| {
            var o = opts;
            sanitizeDistanceParams(&o);
            self.options = o;
            self.window_bits = effectiveWindow(o);
            self.max_backward = (@as(usize, 1) << @intCast(self.window_bits)) - WINDOW_GAP;
            self.match_max_dist = self.max_backward;
            self.refreshDistParams();
        }
        self.buf.clearRetainingCapacity();
        self.consumed = 0;
        self.out.clearRetainingCapacity();
        self.out_pos = 0;
        self.bitbuf.clearRetainingCapacity();
        self.w = .{ .buf = &.{} };
        self.rb = .{};
        self.started = false;
        self.finished_ = false;
        self.failed = false;
        self.input_total_seen = 0;
        self.custom_dict = &.{};
        self.dict_applied = false;
        self.dict_seeded = false;
        self.dict_front_idx = 0;
        self.stream_pos = 0;
        self.p1 = 0;
        self.p2 = 0;
        if (self.options.customDictionary) |d| {
            _ = self.attachDictionary(d);
        }
    }

    /// Compresses a slice of input and returns an allocated output slice.
    pub fn compress(self: *Encoder, input: []const u8) ![]u8 {
        self.reset(null);
        self.options.sizeHint = input.len;
        try self.compressStream(.process, input);
        try self.compressStream(.finish, null);
        const n = self.out.items.len - self.out_pos;
        const result = try self.allocator.alloc(u8, n);
        @memcpy(result, self.out.items[self.out_pos..]);
        self.out_pos = self.out.items.len;
        return result;
    }

    /// Builds the built-in-dictionary match index when quality permits.
    fn ensureStaticLut(self: *Encoder) !?*static_dict.Lut {
        if (self.options.quality < 4) return null;
        if (self.static_lut) |l| return l;
        const l = try self.allocator.create(static_dict.Lut);
        errdefer self.allocator.destroy(l);
        l.* = try static_dict.Lut.build(self.allocator);
        self.static_lut = l;
        return l;
    }

    pub fn setParameter(self: *Encoder, id: u32, value: u32) bool {
        switch (id) {
            paramMode => self.options.mode = Mode.fromInt(value),
            paramQuality => self.options.quality = @min(value, 11),
            paramLgWin => {
                self.options.lgWin = value;
                self.window_bits = effectiveWindow(self.options);
                self.max_backward =
                    (@as(usize, 1) << @intCast(self.window_bits)) - WINDOW_GAP;
                self.match_max_dist = self.max_backward;
            },
            paramLgBlock => self.options.lgBlock = value,
            paramDisableLiteralContextModeling => {
                self.options.disableLiteralContextModeling = value != 0;
            },
            paramSizeHint => self.options.sizeHint = value,
            paramLargeWindow => {
                self.options.largeWindow = value != 0;
                self.window_bits = effectiveWindow(self.options);
                self.max_backward =
                    (@as(usize, 1) << @intCast(self.window_bits)) - WINDOW_GAP;
                self.match_max_dist = self.max_backward;
                self.refreshDistParams();
            },
            paramNPostfix => {
                self.options.nPostfix = value;
                self.refreshDistParams();
            },
            paramNDirect => {
                self.options.nDirect = value;
                self.refreshDistParams();
            },
            else => return false,
        }
        return true;
    }

    pub fn setProgress(self: *Encoder, cb: ?ProgressCallback, ctx: ?*anyopaque) void {
        self.options.progress = cb;
        self.options.progressCtx = ctx;
    }

    fn reportProgress(self: *Encoder) void {
        const cb = self.options.progress orelse return;
        cb(self.options.progressCtx, self.consumed, self.totalTarget());
    }

    fn totalTarget(self: *Encoder) usize {
        if (self.options.sizeHint != 0) return self.options.sizeHint;
        return self.input_total_seen;
    }

    pub fn isFinished(self: *const Encoder) bool {
        return self.finished_;
    }

    pub fn hasMoreOutput(self: *const Encoder) bool {
        return self.out_pos < self.out.items.len;
    }

    pub fn takeOutput(self: *Encoder, dst: []u8) usize {
        const avail = self.out.items.len - self.out_pos;
        const n = @min(avail, dst.len);
        @memcpy(dst[0..n], self.out.items[self.out_pos .. self.out_pos + n]);
        self.out_pos += n;
        if (self.out_pos == self.out.items.len) {
            self.out.clearRetainingCapacity();
            self.out_pos = 0;
        }
        return n;
    }

    /// Attaches a custom dictionary. Must be called before the first
    /// `compressStream`; data is referenced (not copied) and must outlive the
    /// encoder. Decoders must attach the identical bytes to resolve the
    /// dictionary back-references this produces.
    pub fn attachDictionary(self: *Encoder, data: []const u8) bool {
        if (data.len == 0) return true; // soft no-op
        if (data.len > (1 << 24)) return false;
        if (self.started or self.buf.items.len != 0 or self.dict_applied) return false;
        self.custom_dict = data;
        self.dict_applied = true;
        return true;
    }

    pub fn compressStream(self: *Encoder, op: Operation, input: ?[]const u8) !void {
        if (self.failed) return error.BrotliCompressionFailed;
        // Lazily seed the match history with the custom dictionary so LZ77
        // can reference it; `consumed` marks where real output begins.
        if (self.dict_applied and !self.dict_seeded) {
            try self.buf.appendSlice(self.allocator, self.custom_dict);
            self.consumed = self.custom_dict.len;
            self.dict_seeded = true;
            self.dict_front_idx = self.custom_dict.len;
        }
        if (input) |data| {
            // Metadata payloads ride the input parameter but are not stream
            // data; they must never enter the match-history buffer.
            if (op != .emit_metadata) {
                self.input_total_seen += data.len;
                try self.buf.appendSlice(self.allocator, data);
            }
        }

        switch (op) {
            .finish => {
                try self.emitAll(true);
                self.finished_ = true;
                self.reportProgress();
            },
            .flush => {
                try self.emitAll(false);
                self.reportProgress();
            },
            .emit_metadata => {
                const payload = input orelse return error.BrotliCompressionFailed;
                try self.emitMetadataBlock(payload);
            },
            .process => {
                const high_water: usize = 1 << 20;
                while (self.buf.items.len >= self.consumed + high_water) {
                    try self.emitBlock(high_water, false);
                    self.consumed += high_water;
                    try self.compact();
                    self.reportProgress();
                }
            },
        }
        if (op == .process and self.options.progress != null and
            input != null and input.?.len < (1 << 20))
        {
            self.reportProgress();
        }
    }

    fn compact(self: *Encoder) !void {
        // Retain up to max_backward history bytes for cross-block matches.
        const keep_from = if (self.consumed > self.max_backward)
            self.consumed - self.max_backward
        else
            0;
        if (keep_from > (1 << 20)) {
            const keep = self.buf.items[keep_from..];
            std.mem.copyForwards(u8, self.buf.items[0..keep.len], keep);
            self.buf.shrinkRetainingCapacity(keep.len);
            self.consumed -= keep_from;
            self.dict_front_idx -= @min(self.dict_front_idx, keep_from);
        }
    }

    /// Emits a metadata metablock (RFC 7932 section 9.2): ISLAST=0,
    /// MNIBBLES pattern `11`, reserved zero bit, then the payload length in
    /// 1..3 little-endian bytes followed by the byte-aligned payload.
    fn emitMetadataBlock(self: *Encoder, payload: []const u8) !void {
        if (payload.len >= MAX_MLEN) return error.BrotliCompressionFailed;
        try self.writeHeader();
        // The stored length follows the format-wide convention of MLEN-1;
        // an empty payload takes the dedicated zero-byte-count form.
        var nbytes_needed: usize = 0;
        var v: u64 = 0;
        if (payload.len != 0) {
            v = payload.len - 1;
            nbytes_needed =
                if (v <= 0xFF) 1 else if (v <= 0xFFFF) 2 else 3;
            // The final length byte must be nonzero when more than one is
            // present; widen the encoding if the minimal form would end in
            // a zero byte.
            while (nbytes_needed > 1 and
                ((v >> @intCast((nbytes_needed - 1) * 8)) & 0xFF) == 0)
            {
                if (nbytes_needed == 3) return error.BrotliCompressionFailed;
                nbytes_needed += 1;
            }
            if (nbytes_needed > 3) return error.BrotliCompressionFailed;
        }

        try self.reserve(payload.len * 8 + 64);
        self.syncW();

        self.w.put(1, 0); // ISLAST = 0
        self.w.put(2, 3); // MNIBBLES marker for metadata
        self.w.put(1, 0); // reserved
        self.w.put(2, @intCast(nbytes_needed));
        var i: usize = 0;
        while (i < nbytes_needed) : (i += 1) {
            self.w.put(8, v & 0xFF);
            v >>= 8;
        }

        // Byte-align, then copy the raw payload like a stored block body.
        self.w.pos = (self.w.pos + 7) & ~@as(usize, 7);
        const start_byte = self.w.pos >> 3;
        try self.reserve((start_byte + payload.len) * 8 - self.w.pos + 64);
        if (payload.len != 0) {
            @memcpy(
                self.bitbuf.items[start_byte .. start_byte + payload.len],
                payload,
            );
        }
        self.w.pos = (start_byte + payload.len) << 3;
        try self.finalizeBits(false);
    }

    /// Appends finished bytes of the current bit buffer to the output queue.
    /// Non-final blocks carry the partial byte into the next metablock; the
    /// final call zero-pads to a byte boundary instead.
    fn finalizeBits(self: *Encoder, final: bool) !void {
        var nbytes = self.w.pos >> 3;
        const rem = self.w.pos & 7;
        if (final) {
            if (rem != 0) {
                // Low bits already hold data; the reserved tail is zeroed.
                nbytes += 1;
            }
            try self.out.appendSlice(self.allocator, self.bitbuf.items[0..nbytes]);
            self.bitbuf.clearRetainingCapacity();
            self.w.pos = 0;
            return;
        }
        var partial: u8 = 0;
        if (rem != 0) partial = self.bitbuf.items[nbytes];
        try self.out.appendSlice(self.allocator, self.bitbuf.items[0..nbytes]);
        self.bitbuf.clearRetainingCapacity();
        if (rem != 0) {
            try self.bitbuf.resize(self.allocator, 1);
            self.bitbuf.items[0] = partial & ((@as(u8, 1) << @intCast(rem)) - 1);
            self.w.pos = rem;
        } else {
            self.w.pos = 0;
        }
    }

    fn reserve(self: *Encoder, extra_bits: usize) !void {
        const need_bytes = ((self.w.pos + extra_bits + 7) >> 3) + 16;
        const old_len = self.bitbuf.items.len;
        if (old_len >= need_bytes) return;
        try self.bitbuf.resize(self.allocator, need_bytes);
        @memset(self.bitbuf.items[old_len..], 0);
        self.syncW();
    }

    fn syncW(self: *Encoder) void {
        self.w.buf = self.bitbuf.items;
    }

    fn emitAll(self: *Encoder, is_last: bool) !void {
        var remaining = self.buf.items.len - self.consumed;
        if (remaining == 0) {
            if (is_last) {
                try self.writeHeader();
                try self.reserve(64);
                self.syncW();
                self.w.put(1, 1); // ISLAST
                self.w.put(1, 1); // ISLASTEMPTY
                try self.finalizeBits(true);
            }
            return;
        }
        while (remaining > 0) {
            const take = @min(remaining, MAX_MLEN);
            const chunk_last = is_last and take == remaining;
            try self.emitBlock(take, chunk_last);
            self.consumed += take;
            remaining -= take;
            try self.compact();
        }
    }

    fn writeHeader(self: *Encoder) !void {
        if (self.started) return;
        self.started = true;
        try self.reserve(16);

        const wb = self.window_bits;
        if (self.options.largeWindow) {
            // Large-window marker: `1`, `000`, `001`, reserved zero, then six
            // window bits — 14 bits total.
            self.w.put(1, 1);
            self.w.put(3, 0);
            self.w.put(3, 1);
            self.w.put(1, 0);
            self.w.put(6, wb);
        } else if (wb == 16) {
            self.w.put(1, 0);
        } else if (wb == 17) {
            self.w.put(1, 1);
            self.w.put(3, 0);
            self.w.put(3, 0);
        } else if (wb >= 18 and wb <= 24) {
            self.w.put(1, 1);
            self.w.put(3, wb - 17);
        } else {
            self.w.put(1, 1);
            self.w.put(3, 0);
            self.w.put(3, (wb - 8) & 7);
        }
    }

    fn emitBlock(self: *Encoder, mlen: usize, is_last: bool) !void {
        try self.writeHeader();

        // Worst-case bit budget: every input byte as a <=15-bit literal code
        // plus per-command overhead, trees and headers.
        try self.reserve(mlen * 15 + (1 << 20));
        self.syncW();

        // this block carries data).
        self.w.put(1, if (is_last) 1 else 0);
        if (is_last) self.w.put(1, 0);

        // MNIBBLES + MLEN (value stored is MLEN-1).
        const v = mlen - 1;
        const nibbles: usize = if (v < (1 << 16)) 0 else if (v < (1 << 20)) 1 else 2;
        self.w.put(2, @intCast(nibbles));
        const count: usize = 4 + nibbles;
        for (0..count) |i| {
            self.w.put(4, (v >> @intCast(i * 4)) & 0xF);
        }

        if (try self.tryCompressed(mlen, is_last)) {
            try self.finalizeBits(is_last);
            return;
        }

        if (!is_last) {
            // Stored metablock.
            self.w.put(1, 1); // ISUNCOMPRESSED
            self.w.pos = (self.w.pos + 7) & ~@as(usize, 7);
            const start_byte = self.w.pos >> 3;
            const need_bits = (start_byte + mlen) * 8 - self.w.pos + 64;
            try self.reserve(need_bits);
            @memcpy(
                self.bitbuf.items[start_byte .. start_byte + mlen],
                self.buf.items[self.consumed .. self.consumed + mlen],
            );
            self.w.pos = (start_byte + mlen) << 3;
            try self.finalizeBits(true);
            const stored = self.buf.items[self.consumed .. self.consumed + mlen];
            self.stream_pos += mlen;
            self.updatePrev(stored);
            return;
        }

        // Final block must be compressed; emit an all-literals plan.
        try self.emitAllLiterals(mlen);
        try self.finalizeBits(true);
    }

    /// Updates the rolling P1/P2 state after `data` became real output.
    fn updatePrev(self: *Encoder, data: []const u8) void {
        switch (data.len) {
            0 => {},
            1 => {
                self.p2 = self.p1;
                self.p1 = data[0];
            },
            else => {
                self.p1 = data[data.len - 1];
                self.p2 = data[data.len - 2];
            },
        }
    }

    fn emitAllLiterals(self: *Encoder, mlen: usize) !void {
        var lit_tree_freq: [MAX_LIT_TREES][256]u32 = @splat(@splat(0));
        var ic_freq: [704]u32 = @splat(0);
        var dist_freq: [DIST_ALPHABET_MAX]u32 = @splat(0);

        // A single literals-only command; the decoder finishes the metablock
        // right after the insert run, so no copy or distance is consumed.
        const ins = codeFor(&ins_off, @intCast(mlen));
        var sym = cmd_maps.implicit_sym[ins.code][0];
        if (sym == 0xFFFF) sym = cmd_maps.explicit_sym[ins.code][0];

        const data = self.buf.items[self.consumed .. self.consumed + mlen];
        for (data) |b| lit_tree_freq[0][b] += 1;

        const planned = [_]PlannedCommand{.{
            .sym = sym,
            .insert_len = @intCast(mlen),
            .copy_len = 0,
            .copy_code_len = 0,
            .ins_extra = ins.extra,
            .ins_nbits = @intCast(kInsEb[ins.code]),
            .copy_extra = 0,
            .copy_nbits = 0,
            .kind = .literals_only,
        }};
        ic_freq[sym] += 1;

        try self.serializeCompressed(
            true,
            &lit_tree_freq,
            1,
            null,
            null,
            &ic_freq,
            &dist_freq,
            &planned,
            data,
        );
        self.stream_pos += mlen;
        self.updatePrev(data);
    }

    fn tryCompressed(self: *Encoder, mlen: usize, is_last: bool) !bool {
        const alloc = self.allocator;
        const params = qualityParams(self.options.quality);
        const full = self.buf.items;

        const lut = try self.ensureStaticLut();

        var cmds: std.ArrayList(lz77.Command) = .empty;
        defer cmds.deinit(alloc);
        const search_dist = self.match_max_dist + self.dict_front_idx;
        try lz77.compress(alloc, full, self.consumed, self.consumed + mlen, search_dist, params, &cmds, lut);
        if (cmds.items.len == 0) return false;

        var lit_tree_freq: [MAX_LIT_TREES][256]u32 = @splat(@splat(0));
        var ic_freq: [704]u32 = @splat(0);
        var dist_freq: [DIST_ALPHABET_MAX]u32 = @splat(0);

        const planned = try alloc.alloc(PlannedCommand, cmds.items.len + 1);
        defer alloc.free(planned);

        const rb_saved = self.rb;
        const block_stream_base = self.stream_pos;

        // Output cursor (bytes of this block already planned).
        var out_cursor: usize = 0;
        // Insert-run bytes carried forward when an unprofitable dictionary
        // reference gets folded back into literals.
        var carry_insert: usize = 0;
        var used: usize = 0;
        var ok = true;
        for (cmds.items, 0..) |cmd, ci| {
            const ic = codeFor(&ins_off, cmd.insert_len + @as(u32, @intCast(carry_insert)));
            var p: PlannedCommand = undefined;
            p.insert_len = cmd.insert_len + @as(u32, @intCast(carry_insert));
            carry_insert = 0;
            p.copy_len = cmd.copy_len;
            p.copy_code_len = cmd.copy_len;
            p.ins_extra = ic.extra;
            p.ins_nbits = @intCast(kInsEb[ic.code]);
            p.dist_code = 0;
            p.dist_extra = 0;
            p.dist_nbits = 0;

            if (cmd.copy_len == 0) {
                if (ci + 1 != cmds.items.len) {
                    ok = false;
                    break;
                }
                p.copy_extra = 0;
                p.copy_nbits = 0;
                var sym = cmd_maps.implicit_sym[ic.code][0];
                if (sym == 0xFFFF) sym = cmd_maps.explicit_sym[ic.code][0];
                p.sym = sym;
                p.kind = .literals_only;
                planned[used] = p;
                used += 1;
                ic_freq[sym] += 1;
                out_cursor += p.insert_len;
                continue;
            }

            if (cmd.dict) |ref| {
                // Built-in dictionary reference: the stream carries the base
                // word length while the decoder applies the transform.
                const l = ref.len_code;
                if (l < dictionary.min_word_length or l > dictionary.max_word_length) {
                    ok = false;
                    break;
                }
                const abs_pos = block_stream_base + out_cursor + p.insert_len;
                const md: u32 = @intCast(@min(abs_pos, self.max_backward));
                const shift: u5 = @intCast(dictionary.size_bits_by_length[l]);
                const address = (@as(u32, ref.transform_idx) << shift) | ref.word_idx;
                const dist = md + 1 + @as(u32, @intCast(self.custom_dict.len)) + address;
                const dc_ok =
                    dist <= constants.MAX_ALLOWED_DISTANCE and
                    blk: {
                        const dcv = encodeCopyDistance(dist, self.ndirect, self.npostfix) orelse break :blk false;
                        break :blk dcv.sym < self.dist_alphabet_limit and
                            dcv.nbits <= constants.MAX_DISTANCE_BITS;
                    };
                // Profitability: a reference pays for its command symbol,
                // distance symbol and long extra bits; keep it only when it
                // clearly beats emitting those bytes as literals.
                const est_cmd_bits: usize = 24 + 2 * @as(usize, dc_dist_bits(dist));
                if (!dc_ok or @as(usize, cmd.copy_len) * 8 < est_cmd_bits + 16) {
                    // Fold back into literals. The successor absorbs these
                    // bytes plus any carry this command had already taken on.
                    carry_insert += p.insert_len + cmd.copy_len;
                    continue;
                }
                const cc = codeFor(&copy_off, l);
                p.copy_code_len = l;
                p.copy_extra = cc.extra;
                p.copy_nbits = @intCast(kCopyEb[cc.code]);
                const dcv = encodeCopyDistance(dist, self.ndirect, self.npostfix).?;
                const sym = cmd_maps.explicit_sym[ic.code][cc.code];
                if (sym == 0xFFFF) {
                    ok = false;
                    break;
                }
                p.sym = sym;
                p.kind = .explicit_dist;
                p.dist_code = @intCast(dcv.sym);
                p.dist_extra = dcv.extra;
                p.dist_nbits = dcv.nbits;
                dist_freq[dcv.sym] += 1;
                self.rb.push(dist);
                planned[used] = p;

                used += 1;
                ic_freq[p.sym] += 1;
                out_cursor += p.insert_len + p.copy_len;
                continue;
            }

            const cc = codeFor(&copy_off, cmd.copy_len);
            p.copy_extra = cc.extra;
            p.copy_nbits = @intCast(kCopyEb[cc.code]);

            // A source inside the custom dictionary resolves through the
            // decoder's compound-dictionary path; it must use an explicit
            // distance and is only valid while output fits the window.
            const from_dict = self.dict_front_idx > 0 and
                cmd.dist > out_cursor + cmd.insert_len;

            const use_implicit = !from_dict and
                cmd.dist == self.rb.last() and
                cmd_maps.implicit_sym[ic.code][cc.code] != 0xFFFF;

            if (use_implicit) {
                p.sym = cmd_maps.implicit_sym[ic.code][cc.code];
                p.kind = .implicit_last;
            } else {
                if (from_dict) {
                    // Compound references require the whole match to resolve
                    // before the window fills; bail to a safer block layout
                    // otherwise.
                    if (out_cursor + cmd.insert_len > self.max_backward) {
                        ok = false;
                        break;
                    }
                }
                const dc = encodeCopyDistance(cmd.dist, self.ndirect, self.npostfix) orelse {
                    ok = false;
                    break;
                };
                if (dc.sym >= self.dist_alphabet_limit or
                    (!self.options.largeWindow and dc.nbits > constants.MAX_DISTANCE_BITS))
                {
                    ok = false;
                    break;
                }
                const sym = cmd_maps.explicit_sym[ic.code][cc.code];
                if (sym == 0xFFFF) {
                    ok = false;
                    break;
                }
                p.sym = sym;
                p.kind = .explicit_dist;
                p.dist_code = @intCast(dc.sym);
                p.dist_extra = dc.extra;
                p.dist_nbits = dc.nbits;
                dist_freq[dc.sym] += 1;
                self.rb.push(cmd.dist);
            }
            planned[used] = p;

            used += 1;
            ic_freq[p.sym] += 1;
            out_cursor += p.insert_len + p.copy_len;
        }

        if (!ok) {
            self.rb = rb_saved;
            return false;
        }

        // Fold any trailing carried literals into a final literal run.
        if (carry_insert != 0) {
            const ins_t = codeFor(&ins_off, @intCast(carry_insert));
            var sym_t = cmd_maps.implicit_sym[ins_t.code][0];
            if (sym_t == 0xFFFF) sym_t = cmd_maps.explicit_sym[ins_t.code][0];
            planned[used] = .{
                .sym = sym_t,
                .insert_len = @intCast(carry_insert),
                .copy_len = 0,
                .copy_code_len = 0,
                .ins_extra = ins_t.extra,
                .ins_nbits = @intCast(kInsEb[ins_t.code]),
                .copy_extra = 0,
                .copy_nbits = 0,
                .kind = .literals_only,
            };
            used += 1;
            ic_freq[sym_t] += 1;
        }
        const data = self.buf.items[self.consumed .. self.consumed + mlen];

        // Literal layout selection: plain single tree, second-order context
        // modeling, or literal block switching (each block type gets its own
        // tree through an identity context map). All candidates are measured
        // exactly and the cheapest wins.
        var cm: ?CtxPlan = null;
        var split: ?SwitchTables = null;
        {
            var literal_count: usize = 0;
            for (planned[0..used]) |p| literal_count += p.insert_len;
            const want_cm = !self.options.disableLiteralContextModeling and
                self.options.quality >= 4 and mlen >= 128 and literal_count >= 256;
            const want_split = !self.options.disableLiteralContextModeling and
                self.options.quality >= 4 and mlen >= 2048 and literal_count >= 1024;

            // Plain baseline measurement.
            var all: [256]u32 = @splat(0);
            for (data) |b| all[b] += 1;
            const pm = measureTreeBits(&all, 256);
            var best_layout: enum { plain, cm_w, split_w } = .plain;
            var best_bits: usize = pm.stored + pm.payload;
            var cm_cand: ?CtxPlan = null;
            var split_cand: ?SwitchTables = null;

            if (want_cm) {
                const mode = chooseContextMode(data, self.options.quality);
                var ctx_hist: [64][256]u32 = @splat(@splat(0));
                buildContextHistograms(data, mode, self.p1, self.p2, &ctx_hist);
                var plan = CtxPlan{ .mode = mode };
                clusterContexts(&ctx_hist, &lit_tree_freq, &plan.cmap, &plan.ntrees);
                var bits: usize = sizeOfContextMapBits(&plan.cmap) * 4 + 16 + plan.ntrees * 8;
                var t: usize = 0;
                while (t < plan.ntrees) : (t += 1) {
                    const m = measureTreeBits(&lit_tree_freq[t], 256);
                    bits += m.stored + m.payload;
                }
                if (bits < best_bits) {
                    best_bits = bits;
                    best_layout = .cm_w;
                    cm_cand = plan;
                }
            }

            if (want_split) {
                var runs: std.ArrayList(LitRun) = .empty;
                defer runs.deinit(alloc);
                var run_off: usize = 0;
                for (planned[0..used]) |p| {
                    if (p.insert_len != 0) {
                        runs.append(alloc, .{
                            .off = @intCast(run_off),
                            .len = p.insert_len,
                        }) catch break;
                    }
                    run_off += p.insert_len + p.copy_len;
                }
                if (runs.items.len != 0) {
                    const seg_of = alloc.alloc(u8, literal_count) catch return false;
                    defer alloc.free(seg_of);
                    const k = planLiteralSegments(data, runs.items, seg_of);
                    if (k > 1) {
                        var seg_hist: [MAX_LIT_BLOCK_TYPES][256]u32 = @splat(@splat(0));
                        {
                            var li: usize = 0;
                            for (runs.items) |r| {
                                for (data[r.off..][0..r.len]) |b| {
                                    seg_hist[seg_of[li]][b] += 1;
                                    li += 1;
                                }
                            }
                        }
                        for (&lit_tree_freq) |*t| t.* = @splat(0);
                        var t: usize = 0;
                        while (t < k) : (t += 1) lit_tree_freq[t] = seg_hist[t];
                        var st = buildSwitchTables(seg_of);
                        // Switch codes plus the identity context map cost.
                        var bits: usize = @as(usize, k - 1) * 16 + k * 60 + k * 8;
                        t = 0;
                        while (t < k) : (t += 1) {
                            const m = measureTreeBits(&lit_tree_freq[t], 256);
                            bits += m.stored + m.payload;
                        }
                        if (bits + 1500 < best_bits) {
                            best_bits = bits;
                            best_layout = .split_w;
                            split_cand = st;
                            _ = &st;
                        }
                    }
                }
            }

            switch (best_layout) {
                .cm_w => cm = cm_cand,
                .split_w => split = split_cand,
                .plain => {
                    for (data) |b| lit_tree_freq[0][b] += 1;
                },
            }
        }

        // Cheap profitability check against stored representation.
        var cost_bits: usize = 600; // approximate trees + header
        for (planned[0..used]) |p| {
            cost_bits += 8;
            cost_bits += @as(usize, p.ins_nbits) + @as(usize, p.copy_nbits);
            cost_bits += p.insert_len * 6;
            switch (p.kind) {
                .literals_only, .implicit_last => {},
                .explicit_dist => cost_bits += 6 + p.dist_nbits,
            }
        }
        if (!is_last and mlen >= 2048 and cost_bits >= mlen * 8) {
            self.rb = rb_saved;
            return false;
        }

        const ntrees_final: u32 = if (split) |s| s.ntypes else if (cm) |c| c.ntrees else 1;
        try self.serializeCompressed(
            is_last,
            &lit_tree_freq,
            ntrees_final,
            if (cm) |c| c else null,
            split,
            &ic_freq,
            &dist_freq,
            planned[0..used],
            data,
        );
        self.stream_pos += mlen;
        self.updatePrev(data);
        return true;
    }

    fn serializeCompressed(
        self: *Encoder,
        is_last: bool,
        lit_tree_freq: *const [MAX_LIT_TREES][256]u32,
        ntrees_lit: u32,
        cm: ?CtxPlan,
        split_param: ?SwitchTables,
        ic_freq: *const [704]u32,
        dist_freq: *const [DIST_ALPHABET_MAX]u32,
        planned: []const PlannedCommand,
        data: []const u8,
    ) !void {
        var split = split_param;
        var cl_scratch: [18]u8 = undefined;

        // The ISUNCOMPRESSED bit exists only in non-final metablocks.
        if (!is_last) self.w.put(1, 0);

        var sw_type_depths: [MAX_LIT_BLOCK_TYPES + 2]u8 = undefined;
        var sw_type_codes: [MAX_LIT_BLOCK_TYPES + 2]u16 = undefined;
        var sw_len_depths: [constants.NUM_BLOCK_LEN_SYMBOLS]u8 = undefined;
        var sw_len_codes: [constants.NUM_BLOCK_LEN_SYMBOLS]u16 = undefined;

        // Literal category: block count and its switch machinery when more
        // than one block type is present. The initial type zero is implicit,
        // so only the initial block length is coded here.
        if (split) |*s| {
            try self.putVarLenUint8(s.ntypes - 1);
            huff_enc.storeHuffmanTree(
                &self.w,
                s.type_freq[0 .. s.ntypes + 2],
                s.ntypes + 2,
                s.ntypes + 2,
                &sw_type_depths,
                &sw_type_codes,
                cl_scratch[0..],
            );
            huff_enc.storeHuffmanTree(
                &self.w,
                &s.len_freq,
                constants.NUM_BLOCK_LEN_SYMBOLS,
                constants.NUM_BLOCK_LEN_SYMBOLS,
                &sw_len_depths,
                &sw_len_codes,
                cl_scratch[0..],
            );
            const lc0 = blockLengthPrefixCode(s.seg_lens[0]);
            self.w.putBits(@intCast(sw_len_depths[lc0]), sw_len_codes[lc0]);
            self.w.putBits(
                @intCast(prefix_ranges.prefix_code_ranges[lc0].nbits),
                s.seg_lens[0] - prefix_ranges.prefix_code_ranges[lc0].offset,
            );
        } else {
            self.w.put(1, 0); // NBLTYPESL = 1
        }
        self.w.put(1, 0); // NBLTYPESI = 1
        self.w.put(1, 0); // NBLTYPESD = 1

        // NPOSTFIX / NDIRECT as one six-bit field.
        {
            const nd_raw = self.ndirect >> @intCast(self.npostfix);
            self.w.put(6, @as(u64, self.npostfix) | (@as(u64, nd_raw) << 2));
        }

        // One two-bit context mode per literal block type.
        {
            const mode_val: u64 = if (cm) |c| @backingInt(c.mode) else 0;
            const ntypes: usize = if (split) |s| @intCast(s.ntypes) else 1;
            var t: usize = 0;
            while (t < ntypes) : (t += 1) self.w.put(2, mode_val);
        }

        // Literal tree count and context map. With splitting active the map
        // is the identity over each type's 64-context slot, which RLE-codes
        // compactly; with modeling it is the clustered assignment.
        try self.putVarLenUint8(ntrees_lit - 1);
        if (split) |s| {
            var ident: [MAX_LIT_BLOCK_TYPES * 64]u8 = undefined;
            for (&ident, 0..) |*e, i| e.* = @intCast(i / 64);
            try self.emitLiteralContextMap(ident[0 .. @as(usize, s.ntypes) * 64], ntrees_lit);
        } else if (ntrees_lit > 1) {
            try self.emitLiteralContextMap(cm.?.cmap[0..], cm.?.ntrees);
        }

        // Distance tree count: always a single tree.
        self.w.put(1, 0); // NTREESD = 1

        // Literal trees first, then command, then distance — the exact order
        // the decoder consumes them in.
        var lit_depths: [MAX_LIT_TREES][256]u8 = undefined;
        var lit_codes: [MAX_LIT_TREES][256]u16 = undefined;
        {
            var t: usize = 0;
            while (t < ntrees_lit) : (t += 1) {
                huff_enc.storeHuffmanTree(
                    &self.w,
                    &lit_tree_freq[t],
                    256,
                    256,
                    &lit_depths[t],
                    &lit_codes[t],
                    &cl_scratch,
                );
            }
        }

        var ic_depths: [704]u8 = undefined;
        var ic_codes: [704]u16 = undefined;
        huff_enc.storeHuffmanTree(
            &self.w,
            ic_freq,
            constants.NUM_COMMAND_SYMBOLS,
            constants.NUM_COMMAND_SYMBOLS,
            &ic_depths,
            &ic_codes,
            &cl_scratch,
        );

        const d_limit = self.dist_alphabet_limit;
        const d_max = self.dist_alphabet_max;
        const d_depths = try self.allocator.alloc(u8, d_max);
        defer self.allocator.free(d_depths);
        const d_codes = try self.allocator.alloc(u16, d_max);
        defer self.allocator.free(d_codes);
        huff_enc.storeHuffmanTree(
            &self.w,
            dist_freq[0..d_limit],
            d_max,
            d_limit,
            d_depths,
            d_codes,
            &cl_scratch,
        );
        // literal's context id from the running P1/P2 exactly like the
        // decoder reconstructs it from its ring buffer.
        var p1 = self.p1;
        var p2 = self.p2;
        var lit_remaining: u32 = if (split) |s| s.seg_lens[0] else 0;
        var sw_calc = SwitchCalc{};
        var cur_type: u8 = 0;
        var lit_pos: usize = 0;
        for (planned) |p| {
            self.w.putBits(@intCast(ic_depths[p.sym]), ic_codes[p.sym]);
            self.w.putBits(p.ins_nbits, p.ins_extra);
            self.w.putBits(p.copy_nbits, p.copy_extra);

            const tree_of = struct {
                fn go(plan: ?CtxPlan, prev: u8, prev2: u8) usize {
                    const pl = plan orelse return 0;
                    const cid = context.contextId(prev, prev2, pl.mode);
                    return pl.cmap[cid];
                }
            }.go;

            var li: usize = 0;
            while (li < p.insert_len) : (li += 1) {
                if (lit_remaining == 0 and split != null) {
                    const s = &split.?;
                    const t_new: u32 = s.types[s.seg_idx];
                    const tc = nextBlockTypeCode(&sw_calc, t_new);
                    self.w.putBits(@intCast(s.type_depths[tc]), s.type_codes[tc]);
                    const lc = blockLengthPrefixCode(s.seg_lens[s.seg_idx]);
                    self.w.putBits(@intCast(sw_len_depths[lc]), sw_len_codes[lc]);
                    self.w.putBits(
                        @intCast(prefix_ranges.prefix_code_ranges[lc].nbits),
                        s.seg_lens[s.seg_idx] - prefix_ranges.prefix_code_ranges[lc].offset,
                    );
                    lit_remaining = s.seg_lens[s.seg_idx];
                    cur_type = @intCast(t_new);
                    s.seg_idx += 1;
                }
                lit_remaining -|= 1;
                const b = data[lit_pos];
                lit_pos += 1;
                const t: usize = if (split != null) cur_type else tree_of(cm, p1, p2);
                self.w.putBits(@intCast(lit_depths[t][b]), lit_codes[t][b]);
                p2 = p1;
                p1 = b;
            }
            // Copies jump P1/P2 to the tail of the copied region; the source
            // bytes are part of the same real output array.
            if (p.copy_len != 0) {
                const end_pos = lit_pos + p.copy_len;
                if (end_pos >= 2) {
                    p1 = data[end_pos - 1];
                    p2 = data[end_pos - 2];
                } else {
                    p1 = data[end_pos - 1];
                    p2 = 0;
                }
                lit_pos = end_pos;
            }

            switch (p.kind) {
                .literals_only, .implicit_last => {},
                .explicit_dist => {
                    self.w.putBits(@intCast(d_depths[p.dist_code]), d_codes[p.dist_code]);
                    self.w.putBits(p.dist_nbits, p.dist_extra);
                },
            }
        }
        std.debug.assert(lit_pos == data.len);
    }

    fn putVarLenUint8(self: *Encoder, v: u32) !void {
        try self.reserve(16);
        if (v == 0) {
            self.w.put(1, 0);
            return;
        }
        if (v == 1) {
            self.w.put(1, 1);
            self.w.put(3, 0);
            return;
        }
        const nb: u6 = @intCast(std.math.log2_int(u32, v));
        self.w.put(1, 1);
        self.w.put(3, nb);
        self.w.put(nb, v - (@as(u32, 1) << @intCast(nb)));
    }

    /// Emits the literal context map with optional zero-run-length coding
    /// (RFC 7932 section 9.3), choosing the cheaper representation by an
    /// entropy estimate. The inverse-MTF transform is not applied.
    fn emitLiteralContextMap(self: *Encoder, cmap: []const u8, ntrees: u32) !void {
        const alloc = self.allocator;
        const size = cmap.len;

        const RunSym = struct {
            sym: u16,
            extra: u16 = 0,
            nbits: u5 = 0,
        };

        // Build candidate symbol streams for several run-length settings and
        // keep the cheapest.
        var best_rle: u32 = 0; // zero means "RLE disabled"
        var best_cost: f64 = std.math.floatMax(f64);
        var best_syms: []RunSym = &.{};
        defer alloc.free(best_syms);

        var rle_opt: u32 = 0;
        while (rle_opt <= 6) : (rle_opt += 1) {
            var syms: std.ArrayList(RunSym) = .empty;
            defer syms.deinit(alloc);
            var cost: f64 = 5; // prefix bits + IMTF bit overhead

            if (rle_opt == 0) {
                try syms.ensureTotalCapacity(alloc, size);
                var i: usize = 0;
                while (i < size) : (i += 1) {
                    syms.appendAssumeCapacity(.{ .sym = @as(u16, cmap[i]) + 0 });
                }
            } else {
                const rle_max = rle_opt;
                var i: usize = 0;
                while (i < size) {
                    if (cmap[i] != 0) {
                        try syms.append(alloc, .{ .sym = @as(u16, cmap[i]) + @as(u16, @intCast(rle_max)) });
                        i += 1;
                        continue;
                    }
                    var run: usize = 0;
                    while (i + run < size and cmap[i + run] == 0) run += 1;
                    var left = run;
                    while (left > 0) {
                        if (left == 1) {
                            try syms.append(alloc, .{ .sym = 0 });
                            cost += 2;
                            left -= 1;
                        } else {
                            // Largest representable chunk: reps in 2^c..2^(c+1)-1.
                            var cc: u5 = 1;
                            while (cc + 1 <= rle_max and
                                (@as(usize, 1) << @as(u5, @intCast(cc + 1))) <= left) cc += 1;
                            const base_rep = @as(usize, 1) << cc;
                            var extra = left - base_rep;
                            const max_extra = (@as(usize, 1) << cc) - 1;
                            if (extra > max_extra) extra = max_extra;
                            try syms.append(alloc, .{
                                .sym = cc,
                                .extra = @intCast(extra),
                                .nbits = cc,
                            });
                            cost += 2 + @as(f64, @floatFromInt(cc));
                            left -= base_rep + extra;
                        }
                    }
                    i += run;
                }
            }

            // Entropy estimate over this symbol stream.
            var freq: [constants.MAX_CONTEXT_MAP_SYMBOLS]u32 = @splat(0);
            for (syms.items) |s| freq[s.sym] += 1;
            var total: u64 = 0;
            for (freq) |f| total += f;
            if (total != 0) {
                for (freq) |f| {
                    if (f != 0) {
                        const pf: f64 = @floatFromInt(f);
                        cost -= pf * @log2(pf / @as(f64, @floatFromInt(total)));
                    }
                }
            }

            if (cost < best_cost) {
                best_cost = cost;
                best_rle = rle_opt;
                alloc.free(best_syms);
                best_syms = try syms.toOwnedSlice(alloc);
            }
        }

        const rle_max: u32 = best_rle;
        self.reserve(8) catch return error.BrotliCompressionFailed;
        self.syncW();
        if (rle_max == 0) {
            self.w.put(1, 0);
        } else {
            self.w.put(1, 1);
            self.w.put(4, rle_max - 1);
        }

        const alphabet: u32 = ntrees + rle_max;
        var freq: [constants.MAX_CONTEXT_MAP_SYMBOLS]u32 = @splat(0);
        for (best_syms) |s| freq[s.sym] += 1;

        var depths: [constants.MAX_CONTEXT_MAP_SYMBOLS]u8 = undefined;
        var codes: [constants.MAX_CONTEXT_MAP_SYMBOLS]u16 = undefined;
        var cl_scratch: [18]u8 = undefined;
        huff_enc.storeHuffmanTree(&self.w, freq[0..alphabet], alphabet, alphabet, &depths, &codes, &cl_scratch);

        for (best_syms) |s| {
            self.w.putBits(@intCast(depths[s.sym]), codes[s.sym]);
            self.w.putBits(s.nbits, s.extra);
        }
        self.w.put(1, 0); // no inverse MTF
    }
};

// ---------------------------------------------------------------------------
// Literal context-modeling helpers
// ---------------------------------------------------------------------------

/// UTF-8 lead/continuation consistency ratio, mirroring the reference
/// detector: a byte pair is "good" when it forms valid UTF-8 structure.
fn isMostlyUTF8(data: []const u8) bool {
    if (data.len == 0) return true;
    var good: usize = 0;
    var checked: usize = 0;
    var i: usize = 0;
    const n = @min(data.len, 1 << 16); // bounded sampling window
    while (i < n) {
        const b = data[i];
        if (b < 0x80) {
            i += 1;
            continue;
        }
        const len: usize = if (b >= 0xF0) 4 else if (b >= 0xE0) 3 else if (b >= 0xC0) 2 else 0;
        checked += 1;
        if (len == 0 or i + len > data.len) {
            i += 1;
            continue;
        }
        var ok = true;
        for (data[i + 1 .. i + len]) |cc| {
            if ((cc & 0xC0) != 0x80) {
                ok = false;
                break;
            }
        }
        if (ok) good += 1;
        i += len;
    }
    if (checked == 0) return true;
    return @as(f64, @floatFromInt(good)) / @as(f64, @floatFromInt(checked)) >= 0.75;
}

/// Chooses the literal context mode for a metablock: UTF8 modeling unless
/// the data is non-UTF8 binary at the highest quality tiers, which prefer
/// signed-byte contexts.
fn chooseContextMode(data: []const u8, quality: u32) context.ContextType {
    if (quality >= 10 and !isMostlyUTF8(data)) return .signed;
    return .utf8;
}

/// Per-context literal histogram over one metablock; P1/P2 start from the
/// rolling state carried across blocks so decoder views stay identical.
fn buildContextHistograms(
    data: []const u8,
    mode: context.ContextType,
    p1_init: u8,
    p2_init: u8,
    out: *[64][256]u32,
) void {
    var p1 = p1_init;
    var p2 = p2_init;
    for (data) |b| {
        const cid = context.contextId(p1, p2, mode);
        out[cid][b] += 1;
        p2 = p1;
        p1 = b;
    }
}

fn histEntropy(h: *const [256]u32) f64 {
    var total: u64 = 0;
    for (h) |f| total += f;
    if (total == 0) return 0;
    var e: f64 = 0;
    const tf: f64 = @floatFromInt(total);
    for (h) |f| {
        if (f != 0) {
            const ff: f64 = @floatFromInt(f);
            e -= ff * @log2(ff / tf);
        }
    }
    return e;
}

/// Rough emitted-size estimate for a context map: one symbol per non-zero
/// entry plus one symbol per zero run, times a few bits each.
fn sizeOfContextMapBits(cmap: *const [64]u8) usize {
    var syms: usize = 0;
    var i: usize = 0;
    while (i < cmap.len) {
        if (cmap[i] != 0) {
            syms += 1;
            i += 1;
        } else {
            while (i < cmap.len and cmap[i] == 0) i += 1;
            syms += 1;
        }
    }
    return syms * 4 + 8;
}

/// Serializes one prefix tree into a scratch sink; returns its exact stored
/// bit count plus the weighted literal-payload bit count it would produce.
fn measureTreeBits(freqs: []const u32, alphabet: u32) struct { stored: usize, payload: usize } {
    var buf: [16384]u8 = @splat(0);
    var w = huff_enc.BitSink{ .buf = &buf };
    var depths: [MAX_ALPHABET_SCRATCH]u8 = undefined;
    var codes: [MAX_ALPHABET_SCRATCH]u16 = undefined;
    var cl: [18]u8 = undefined;
    huff_enc.storeHuffmanTree(&w, freqs, alphabet, alphabet, &depths, &codes, &cl);
    var payload: usize = 0;
    for (freqs, 0..) |f, s| {
        if (f != 0) payload += @as(usize, f) * depths[s];
    }
    return .{ .stored = w.pos, .payload = payload };
}

const MAX_ALPHABET_SCRATCH = 704;

/// Greedy bottom-up clustering of context histograms. Contexts merge while
/// the estimated bit saving beats `CLUSTER_MIN_SAVING`; the cluster count is
/// then forced down to `MAX_LIT_TREES` with the cheapest-loss merges.
/// Produces the per-tree frequency tables and the 64-entry context map.
fn clusterContexts(
    ctx_hist: *const [64][256]u32,
    lit_tree_freq: *[MAX_LIT_TREES][256]u32,
    cmap: *[64]u8,
    ntrees_out: *u32,
) void {
    // Working state: up to 64 singleton clusters.
    var hists: [64][256]u32 = undefined;
    var members: [64]u64 = undefined; // bitmask of contexts in each cluster
    var ent: [64]f64 = undefined;
    var alive: [64]bool = @splat(false);
    var ctx_cluster: [64]usize = undefined;

    var count: usize = 0;
    for (0..64) |c| {
        var total: u64 = 0;
        for (ctx_hist[c]) |f| total += f;
        if (total == 0) {
            cmap[c] = 0;
            ctx_cluster[c] = std.math.maxInt(usize);
            continue;
        }
        hists[count] = ctx_hist[c];
        members[count] = @as(u64, 1) << @intCast(c);
        ent[count] = histEntropy(&hists[count]);
        ctx_cluster[c] = count;
        alive[count] = true;
        count += 1;
    }
    if (count == 0) {
        ntrees_out.* = 1;
        return;
    }

    // Beneficial merges first.
    while (count > MAX_LIT_TREES or true) {
        var best_i: usize = 0;
        var best_j: usize = 0;
        var best_gain: f64 = 0;
        var i: usize = 0;
        while (i < 64) : (i += 1) {
            if (!alive[i]) continue;
            var j = i + 1;
            while (j < 64) : (j += 1) {
                if (!alive[j]) continue;
                var merged: [256]u32 = undefined;
                for (0..256) |k| merged[k] = hists[i][k] + hists[j][k];
                const gain = ent[i] + ent[j] - histEntropy(&merged);
                if (gain > best_gain) {
                    best_gain = gain;
                    best_i = i;
                    best_j = j;
                }
            }
        }
        if (count > MAX_LIT_TREES) {
            // Forced reduction: take whatever pair exists.
            if (best_j == 0 and best_i == 0 and best_gain == 0) {
                // find any two alive
                outer: for (0..64) |a| {
                    if (!alive[a]) continue;
                    var b = a + 1;
                    while (b < 64) : (b += 1) {
                        if (alive[b]) {
                            best_i = a;
                            best_j = b;
                            break :outer;
                        }
                    }
                }
            }
        } else if (best_gain <= CLUSTER_MIN_SAVING) {
            break;
        } else if (best_j <= best_i) {
            // no beneficial pair found (best_* remain zero-initialized)
            if (best_gain == 0) break;
        }
        if (best_i == best_j) break;

        // Merge j into i.
        for (0..256) |k| hists[best_i][k] += hists[best_j][k];
        members[best_i] |= members[best_j];
        ent[best_i] = histEntropy(&hists[best_i]);
        alive[best_j] = false;
        count -= 1;
        if (count == 1) break;
    }

    // Dense-remap surviving clusters by descending size into tree slots.
    const Slot = struct { idx: usize, total: u64 };
    var slots: [MAX_LIT_TREES]Slot = undefined;
    var used: usize = 0;
    for (0..64) |c| {
        if (!alive[c]) continue;
        var total: u64 = 0;
        for (hists[c]) |f| total += f;
        if (used < MAX_LIT_TREES) {
            slots[used] = .{ .idx = c, .total = total };
            used += 1;
        } else {
            // Replace the smallest slot when this cluster is larger.
            var min_k: usize = 0;
            for (1..used) |k| {
                if (slots[k].total < slots[min_k].total) min_k = k;
            }
            if (total > slots[min_k].total) {
                slots[min_k] = .{ .idx = c, .total = total };
            }
        }
    }
    std.mem.sort(Slot, slots[0..used], {}, struct {
        fn lt(_: void, a: Slot, b: Slot) bool {
            return a.total > b.total;
        }
    }.lt);

    for (lit_tree_freq[0..]) |*t| t.* = @splat(0);
    for (slots[0..used], 0..) |slot, t| {
        lit_tree_freq[t] = hists[slot.idx];
    }
    var map: [64]u8 = @splat(0);
    for (0..used) |t| {
        var mset = members[slots[t].idx];
        while (mset != 0) {
            const c = @ctz(mset);
            mset &= mset - 1;
            map[c] = @intCast(t);
        }
    }
    cmap.* = map;
    ntrees_out.* = @max(1, @as(u32, @intCast(used)));
}

/// Upper bound on compressed size for a given input size.
pub fn maxCompressedSize(input_size: usize) usize {
    if (input_size == 0) return 2;
    const num_large_blocks = input_size >> 14;
    const overhead = 2 + 4 * num_large_blocks + 4;
    const result = input_size +% overhead;
    if (result < input_size) return 0;
    return result;
}

/// Compress a complete byte slice in one call with default options.
pub fn compress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return compressWithOptions(allocator, input, .{});
}

/// Compress a complete byte slice in one call with explicit options.
pub fn compressWithOptions(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: Options,
) ![]u8 {
    var enc = Encoder.init(allocator, options);
    defer enc.deinit();
    enc.options.sizeHint = input.len;

    enc.compressStream(.process, input) catch return error.BrotliCompressionError;
    enc.compressStream(.finish, null) catch return error.BrotliCompressionError;

    const n = enc.out.items.len - enc.out_pos;
    const result = try allocator.alloc(u8, n);
    @memcpy(result, enc.out.items[enc.out_pos..]);
    enc.out_pos = enc.out.items.len;
    return result;
}

const testing = std.testing;

test "distance encoding covers small distances" {
    const e1 = encodeCopyDistance(1, 0, 0).?;
    try testing.expectEqual(@as(u32, 16), e1.sym);
    try testing.expectEqual(@as(u32, 0), e1.extra);
    const e2 = encodeCopyDistance(2, 0, 0).?;
    try testing.expectEqual(@as(u32, 16), e2.sym);
    try testing.expectEqual(@as(u32, 1), e2.extra);
    const e3 = encodeCopyDistance(3, 0, 0).?;
    try testing.expectEqual(@as(u32, 17), e3.sym);
}

test "distance encoding round-trips through offsets" {
    // Verify symbol/extra pairs against an independently built LUT for
    // several postfix/direct configurations.
    inline for (.{ .{ 0, 0 }, .{ 1, 0 }, .{ 2, 4 }, .{ 3, 120 }, .{ 0, 24 } }) |cfg| {
        const np: u32 = cfg[0];
        const nd_raw: u32 = cfg[1];
        const nd: u32 = nd_raw << @intCast(np);
        var d: u32 = 1;
        while (d < 100000) : (d += 1) {
            const enc = encodeCopyDistance(d, nd, np) orelse continue;
            // Rebuild the decoder offset for this symbol.
            const postfix = @as(u32, 1) << @intCast(np);
            var off: u32 = undefined;
            var nbits: u5 = undefined;
            if (enc.sym < constants.NUM_DISTANCE_SHORT_CODES + nd) {
                try testing.expect(d == enc.sym - constants.NUM_DISTANCE_SHORT_CODES + 1);
                continue;
            }
            const rel = enc.sym - constants.NUM_DISTANCE_SHORT_CODES - nd;
            const group = rel >> np;
            const pv = rel & (postfix - 1);
            nbits = @intCast((group >> 1) + 1);
            const half: u32 = group & 1;
            off = nd + (((2 + half) << @intCast(nbits)) - 4) * postfix + 1 + pv;
            const dist = off + (@as(u32, enc.extra) << @intCast(np));
            try testing.expectEqual(d, dist);
            try testing.expectEqual(enc.nbits, nbits);
        }
    }
}

test "command maps cover every insert/copy combination" {
    var ic: usize = 0;
    while (ic < 24) : (ic += 1) {
        var jc: usize = 0;
        while (jc < 24) : (jc += 1) {
            try testing.expect(cmd_maps.explicit_sym[ic][jc] != 0xFFFF);
        }
    }
}
