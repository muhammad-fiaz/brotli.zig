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
};

/// Optional progress observer fired while large inputs are compressed.
pub const ProgressCallback = *const fn (
    ctx: ?*anyopaque,
    bytes_done: usize,
    bytes_total: usize,
) void;

pub const Options = struct {
    quality: u32 = 11,
    lgwin: u32 = 22,
    mode: Mode = .generic,
    lgblock: u32 = 0,
    disable_literal_context_modeling: bool = false,
    size_hint: usize = 0,
    large_window: bool = false,
    npostfix: u32 = 0,
    ndirect: u32 = 0,
    progress: ?ProgressCallback = null,
    progress_ctx: ?*anyopaque = null,
};

/// Parameter identifiers, mirroring the C enumeration values.
pub const PARAM_MODE = 0;
pub const PARAM_QUALITY = 1;
pub const PARAM_LGWIN = 2;
pub const PARAM_LGBLOCK = 3;
pub const PARAM_DISABLE_LITERAL_CONTEXT_MODELING = 4;
pub const PARAM_SIZE_HINT = 5;
pub const PARAM_LARGE_WINDOW = 6;
pub const PARAM_NPOSTFIX = 7;
pub const PARAM_NDIRECT = 8;

const MAX_MLEN = 1 << 24;
const WINDOW_GAP = 16;
const MIN_WINDOW = 10;
const MAX_WINDOW = 24;
/// Distance alphabet size for NPOSTFIX=0/NDIRECT=0, MAX_DISTANCE_BITS=24.
const DIST_ALPHABET = 64;

fn effectiveWindow(opts: Options) u32 {
    var w = opts.lgwin;
    if (w < MIN_WINDOW) w = MIN_WINDOW;
    if (w > MAX_WINDOW) w = MAX_WINDOW;
    return w;
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

const DistLut = struct {
    eb: [DIST_ALPHABET]u5 = undefined,
    off: [DIST_ALPHABET]u32 = undefined,

    fn init() DistLut {
        var l: DistLut = undefined;
        var bits: u32 = 1;
        var half: u32 = 0;
        var i: usize = constants.NUM_DISTANCE_SHORT_CODES;
        while (i < DIST_ALPHABET) {
            const base: u32 = (((2 + half) << @intCast(bits)) - 4) + 1;
            l.eb[i] = @intCast(bits);
            l.off[i] = base;
            i += 1;
            bits += half;
            half ^= 1;
        }
        return l;
    }

    fn codeFor(self: *const DistLut, d: u32) ?struct { code: u8, extra: u32 } {
        if (d == 0) return null;
        var c: usize = constants.NUM_DISTANCE_SHORT_CODES;
        while (c < DIST_ALPHABET) : (c += 1) {
            const span = @as(u32, 1) << self.eb[c];
            if (d >= self.off[c] and d < self.off[c] + span) {
                return .{ .code = @intCast(c), .extra = d - self.off[c] };
            }
        }
        return null;
    }
};

const dist_lut = DistLut.init();

const PlanKind = enum { literals_only, implicit_last, explicit_dist };

const PlannedCommand = struct {
    sym: u16,
    insert_len: u32,
    copy_len: u32,
    ins_extra: u32,
    ins_nbits: u5,
    copy_extra: u32,
    copy_nbits: u5,
    kind: PlanKind,
    dist_code: u8 = 0,
    dist_extra: u32 = 0,
};

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

    pub fn init(allocator: std.mem.Allocator, options: Options) Encoder {
        const wb = effectiveWindow(options);
        const max_back = (@as(usize, 1) << @intCast(wb)) - WINDOW_GAP;
        return .{
            .allocator = allocator,
            .options = options,
            .window_bits = wb,
            .max_backward = max_back,
            .match_max_dist = max_back,
        };
    }

    pub fn deinit(self: *Encoder) void {
        self.buf.deinit(self.allocator);
        self.out.deinit(self.allocator);
        self.bitbuf.deinit(self.allocator);
    }

    pub fn setParameter(self: *Encoder, id: u32, value: u32) bool {
        switch (id) {
            PARAM_MODE => self.options.mode = Mode.fromInt(value),
            PARAM_QUALITY => self.options.quality = @min(value, 11),
            PARAM_LGWIN => {
                self.options.lgwin = value;
                self.window_bits = effectiveWindow(self.options);
                self.max_backward =
                    (@as(usize, 1) << @intCast(self.window_bits)) - WINDOW_GAP;
                self.match_max_dist = self.max_backward;
            },
            PARAM_LGBLOCK => self.options.lgblock = value,
            PARAM_DISABLE_LITERAL_CONTEXT_MODELING => {
                self.options.disable_literal_context_modeling = value != 0;
            },
            PARAM_SIZE_HINT => self.options.size_hint = value,
            PARAM_LARGE_WINDOW => self.options.large_window = value != 0,
            PARAM_NPOSTFIX => self.options.npostfix = value,
            PARAM_NDIRECT => self.options.ndirect = value,
            else => return false,
        }
        return true;
    }

    pub fn setProgress(self: *Encoder, cb: ?ProgressCallback, ctx: ?*anyopaque) void {
        self.options.progress = cb;
        self.options.progress_ctx = ctx;
    }

    fn reportProgress(self: *Encoder) void {
        const cb = self.options.progress orelse return;
        cb(self.options.progress_ctx, self.consumed, self.totalTarget());
    }

    fn totalTarget(self: *Encoder) usize {
        if (self.options.size_hint != 0) return self.options.size_hint;
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
            self.input_total_seen += data.len;
            try self.buf.appendSlice(self.allocator, data);
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
        if (wb == 16) {
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

        // ISLAST; when set, the ISLASTEMPTY flag always follows (0 here ï¿½
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
            return;
        }

        // Final block must be compressed; emit an all-literals plan.
        try self.emitAllLiterals(mlen);
        try self.finalizeBits(true);
    }

    fn emitAllLiterals(self: *Encoder, mlen: usize) !void {
        var lit_freq = [_]u32{0} ** 256;
        var ic_freq = [_]u32{0} ** 704;
        var dist_freq = [_]u32{0} ** DIST_ALPHABET;

        // A single literals-only command; the decoder finishes the metablock
        // right after the insert run, so no copy or distance is consumed.
        const ins = codeFor(&ins_off, @intCast(mlen));
        var sym = cmd_maps.implicit_sym[ins.code][0];
        if (sym == 0xFFFF) sym = cmd_maps.explicit_sym[ins.code][0];

        const data = self.buf.items[self.consumed .. self.consumed + mlen];
        for (data) |b| lit_freq[b] += 1;

        const planned = [_]PlannedCommand{.{
            .sym = sym,
            .insert_len = @intCast(mlen),
            .copy_len = 0,
            .ins_extra = ins.extra,
            .ins_nbits = @intCast(kInsEb[ins.code]),
            .copy_extra = 0,
            .copy_nbits = 0,
            .kind = .literals_only,
        }};
        ic_freq[sym] += 1;

        try self.serializeCompressed(true, &lit_freq, &ic_freq, &dist_freq, &planned, data);
    }

    fn tryCompressed(self: *Encoder, mlen: usize, is_last: bool) !bool {
        const alloc = self.allocator;
        const params = qualityParams(self.options.quality);
        const full = self.buf.items;

        var cmds: std.ArrayList(lz77.Command) = .empty;
        defer cmds.deinit(alloc);
        const search_dist = self.match_max_dist + self.dict_front_idx;
        try lz77.compress(alloc, full, self.consumed, self.consumed + mlen, search_dist, params, &cmds);
        if (cmds.items.len == 0) return false;

        var lit_freq = [_]u32{0} ** 256;
        var ic_freq = [_]u32{0} ** 704;
        var dist_freq = [_]u32{0} ** DIST_ALPHABET;

        const planned = try alloc.alloc(PlannedCommand, cmds.items.len);
        defer alloc.free(planned);

        const rb_saved = self.rb;

        // Output cursor (bytes of this block already planned) and the dict
        // boundary in current buffer coordinates.
        var out_cursor: usize = 0;
        var ok = true;
        for (cmds.items, 0..) |cmd, ci| {
            const ic = codeFor(&ins_off, cmd.insert_len);
            var p: PlannedCommand = undefined;
            p.insert_len = cmd.insert_len;
            p.copy_len = cmd.copy_len;
            p.ins_extra = ic.extra;
            p.ins_nbits = @intCast(kInsEb[ic.code]);

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
                planned[ci] = p;
                ic_freq[sym] += 1;
                out_cursor += cmd.insert_len;
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

            var use_implicit = !from_dict and
                cmd.dist == self.rb.last() and
                cmd_maps.implicit_sym[ic.code][cc.code] != 0xFFFF;
            _ = &use_implicit;

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
                const dc = dist_lut.codeFor(cmd.dist) orelse {
                    ok = false;
                    break;
                };
                const sym = cmd_maps.explicit_sym[ic.code][cc.code];
                if (sym == 0xFFFF) {
                    ok = false;
                    break;
                }
                p.sym = sym;
                p.kind = .explicit_dist;
                p.dist_code = dc.code;
                p.dist_extra = dc.extra;
                dist_freq[dc.code] += 1;
                self.rb.push(cmd.dist);
            }
            planned[ci] = p;
            ic_freq[p.sym] += 1;
            out_cursor += cmd.insert_len + cmd.copy_len;
        }

        if (!ok) {
            self.rb = rb_saved;
            return false;
        }

        // Literal frequencies over the exact byte range of this block.
        for (self.buf.items[self.consumed .. self.consumed + mlen]) |b| {
            lit_freq[b] += 1;
        }

        // Cheap profitability check against stored representation.
        var cost_bits: usize = 600; // approximate trees + header
        for (planned) |p| {
            cost_bits += 8;
            cost_bits += @as(usize, p.ins_nbits) + @as(usize, p.copy_nbits);
            cost_bits += p.insert_len * 6;
            switch (p.kind) {
                .literals_only, .implicit_last => {},
                .explicit_dist => cost_bits += 6 + dist_lut.eb[p.dist_code],
            }
        }
        if (!is_last and mlen >= 2048 and cost_bits >= mlen * 8) {
            self.rb = rb_saved;
            return false;
        }

        try self.serializeCompressed(is_last, &lit_freq, &ic_freq, &dist_freq, planned, self.buf.items[self.consumed .. self.consumed + mlen]);
        return true;
    }

    fn serializeCompressed(
        self: *Encoder,
        is_last: bool,
        lit_freq: *[256]u32,
        ic_freq: *[704]u32,
        dist_freq: *[DIST_ALPHABET]u32,
        planned: []const PlannedCommand,
        data: []const u8,
    ) !void {
        var depths: [256]u8 = undefined;
        var codes: [256]u16 = undefined;
        var cl_scratch: [18]u8 = undefined;

        // The ISUNCOMPRESSED bit exists only in non-final metablocks.
        if (!is_last) self.w.put(1, 0);
        self.w.put(1, 0); // NBLTYPESL = 1
        self.w.put(1, 0); // NBLTYPESI = 1
        self.w.put(1, 0); // NBLTYPESD = 1
        self.w.put(6, 0); // NPOSTFIX=0, NDIRECT=0
        self.w.put(2, 0); // context mode LSB6
        self.w.put(1, 0); // NTREESL = 1
        self.w.put(1, 0); // NTREESD = 1

        huff_enc.storeHuffmanTree(&self.w, lit_freq, 256, 256, &depths, &codes, &cl_scratch);

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

        var d_depths: [DIST_ALPHABET]u8 = undefined;
        var d_codes: [DIST_ALPHABET]u16 = undefined;
        huff_enc.storeHuffmanTree(
            &self.w,
            dist_freq,
            DIST_ALPHABET,
            DIST_ALPHABET,
            &d_depths,
            &d_codes,
            &cl_scratch,
        );

        var lit_pos: usize = 0;
        for (planned) |p| {
            self.w.putBits(@intCast(ic_depths[p.sym]), ic_codes[p.sym]);
            self.w.putBits(p.ins_nbits, p.ins_extra);
            self.w.putBits(p.copy_nbits, p.copy_extra);

            var li: usize = 0;
            while (li < p.insert_len) : (li += 1) {
                const b = data[lit_pos];
                lit_pos += 1;
                self.w.putBits(@intCast(depths[b]), codes[b]);
            }
            lit_pos += p.copy_len;

            switch (p.kind) {
                .literals_only, .implicit_last => {},
                .explicit_dist => {
                    self.w.putBits(@intCast(d_depths[p.dist_code]), d_codes[p.dist_code]);
                    self.w.putBits(dist_lut.eb[p.dist_code], p.dist_extra);
                },
            }
        }
        std.debug.assert(lit_pos == data.len);
    }
};

const testing = std.testing;

test "dist lut covers small distances" {
    try testing.expectEqual(@as(u8, 16), dist_lut.codeFor(1).?.code);
    try testing.expectEqual(@as(u8, 16), dist_lut.codeFor(2).?.code);
    try testing.expectEqual(@as(u32, 0), dist_lut.codeFor(1).?.extra);
    try testing.expectEqual(@as(u32, 1), dist_lut.codeFor(2).?.extra);
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
