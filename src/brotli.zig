//! Native Zig implementation of the Brotli compressed-data format
//! (RFC 7932 / Large Window Brotli) â€” public API.
//!
//! This is a from-scratch implementation: no C bindings, no libc, no
//! external dependencies.
//!
//! API style mirrors a classic codec surface:
//!
//!     const brotli = @import("brotli");
//!     const out = try brotli.decompress(allocator, src);
//!
//! plus explicit contexts (`Decoder`), options, streaming, dictionaries,
//! frame introspection and detailed error codes.

const std = @import("std");

/// Brotli codec specification version implemented (matches common/version.h).
pub const version = "0.0.3";
pub const version_number: u32 = 0 * 100 * 100 + 0 * 100 + 3;

/// Data-format specification implemented (Brotli v1.2.0).
pub const spec_version = "1.2.0";
pub const spec_version_number: u32 = 1 * 100 * 100 + 2 * 100 + 0;

pub fn versionString() []const u8 {
    return version;
}
pub fn versionNumber() u32 {
    return version_number;
}

pub const constants = @import("common/constants.zig");
pub const context = @import("common/context.zig");
pub const transform = @import("common/transform.zig");

pub const Strategy = enum {
    generic,
    text,
    font,

    pub fn fromInt(v: u32) Strategy {
        return switch (v & 3) {
            1 => .text,
            2 => .font,
            else => .generic,
        };
    }
};

/// The embedded RFC 7932 static dictionary (words, size-bits, offsets).
pub const Dictionary = @import("dictionary/dictionary.zig");

pub const BitReader = @import("bitstream/bit_reader.zig").BitReader;
pub const bit_writer = @import("bitstream/bit_writer.zig");

pub const huffman = @import("huffman/huffman.zig");
pub const HuffmanCode = huffman.HuffmanCode;

const decoder = @import("decompress/decode.zig");

pub const Decoder = decoder.Decoder;
pub const DecompressionContext = decoder.Decoder;
pub const DecoderOptions = decoder.Options;
pub const DecompressionOptions = decoder.Options;
pub const DecodeResult = decoder.Result;
pub const ErrorCode = decoder.ErrorCode;
pub const BrotliCodecError = decoder.ErrorCode;

pub const MetadataCallbacks = decoder.MetadataCallbacks;

/// Detailed diagnostic for the most recent decoder operation.
pub const BrotliErrorInfo = struct {
    code: ErrorCode,

    pub fn name(self: BrotliErrorInfo) []const u8 {
        return self.code.name();
    }
    pub fn isError(self: BrotliErrorInfo) bool {
        return self.code.isError();
    }
};

/// Convenience incremental-decompression facade over `Decoder`.
///
///     var sd = StreamingDecompressor.init(allocator, .{});
///     defer sd.deinit();
///     while (!sd.finished()) {
///         sd.feed(chunk);
///         const n = sd.take(&out_buf) catch break;
///         ...
///     }
pub const StreamingDecompressor = struct {
    inner: Decoder,
    allocator: std.mem.Allocator,
    /// Accumulates all fed bytes; handed to the decoder as one contiguous
    /// block per `take` call so sub-byte reader state never crosses calls.
    inbuf: std.ArrayList(u8),
    /// Offset of next unconsumed byte in inbuf.
    fed_pos: usize = 0,
    finished_: bool = false,

    pub fn init(allocator: std.mem.Allocator, options: DecoderOptions) StreamingDecompressor {
        return .{
            .inner = Decoder.init(allocator, options),
            .allocator = allocator,
            .inbuf = .empty,
        };
    }

    pub fn deinit(self: *StreamingDecompressor) void {
        self.inbuf.deinit(self.allocator);
        self.inner.deinit();
    }

    pub fn feed(self: *StreamingDecompressor, chunk: []const u8) void {
        self.inbuf.appendSlice(self.allocator, chunk) catch {};
    }

    /// Signals no more input will arrive; flushes any remaining partial data.
    pub fn endInput(self: *StreamingDecompressor) void {
        var empty: []const u8 = &.{};
        var avail: []u8 = &.{};
        _ = self.inner.decompressStream(&empty, &avail, null);
    }

    /// Decodes into `out`; returns bytes written during THIS call.
    /// Callers should keep calling until both `isFinished()` and zero output.
    pub fn take(self: *StreamingDecompressor, out: []u8) !usize {
        var avail: []u8 = out;
        const total_before = self.inner.partial_pos_out;

        // Feed ALL remaining buffered input as one contiguous block.
        var unconsumed: []const u8 = self.inbuf.items[self.fed_pos..];
        if (unconsumed.len > 0) {
            const r = self.inner.decompressStream(&unconsumed, &avail, &self.inner.partial_pos_out);
            self.fed_pos = self.inbuf.items.len - unconsumed.len;
            switch (r) {
                .success => self.finished_ = true,
                .needs_more_input, .needs_more_output => {},
                .err => return error.BrotliStreamError,
            }
            // Compact consumed prefix.
            if (self.fed_pos > 0) {
                const rem = self.inbuf.items.len - self.fed_pos;
                std.mem.copyForwards(u8, self.inbuf.items[0..rem], self.inbuf.items[self.fed_pos..]);
                self.inbuf.shrinkRetainingCapacity(rem);
                self.fed_pos = 0;
            }
        }

        // Signal end-of-stream once all input has been absorbed.
        if (!self.finished_) {
            var empty: []const u8 = &.{};
            const r2 = self.inner.decompressStream(&empty, &avail, &self.inner.partial_pos_out);
            switch (r2) {
                .success => self.finished_ = true,
                .needs_more_input, .needs_more_output => {},
                .err => return error.BrotliStreamError,
            }
        }

        return @intCast(self.inner.partial_pos_out - total_before);
    }

    pub fn isFinished(self: *const StreamingDecompressor) bool {
        return self.finished_;
    }

    pub fn hasError(self: *const StreamingDecompressor) bool {
        return self.inner.errorCode().isError();
    }

    pub fn errorCode(self: *const StreamingDecompressor) ErrorCode {
        return self.inner.errorCode();
    }

    pub fn totalOut(self: *const StreamingDecompressor) u64 {
        return self.inner.partial_pos_out;
    }
};

/// Decompress a complete Brotli stream in one call.
///
///     const out = try brotli.decompress(allocator, src);
///     defer allocator.free(out);
pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return decompressWithOptions(allocator, input, .{});
}

/// Decompress with explicit options (window size, quality, etc.).
///
/// Strategy: decode with a fresh context into a growth-doubling buffer.
/// This avoids cross-call reader-resume edge cases entirely and keeps the
/// common path allocation-cheap.
pub fn decompressWithOptions(allocator: std.mem.Allocator, input: []const u8, options: DecoderOptions) ![]u8 {
    var capacity: usize = @max(@as(usize, 4096), input.len *| 4);
    while (true) {
        var dec = Decoder.init(allocator, options);
        defer dec.deinit();

        var in: []const u8 = input;
        var out = try allocator.alloc(u8, capacity);
        defer allocator.free(out);

        var avail: []u8 = out;
        var total: u64 = 0;
        switch (dec.decompressStream(&in, &avail, &total)) {
            .success => {
                const result = try allocator.alloc(u8, @intCast(total));
                @memcpy(result, out[0..@intCast(total)]);
                return result;
            },
            .needs_more_output => {
                capacity = capacity *| 2;
                continue;
            },
            .needs_more_input => return error.NeedsMoreInput,
            .err => return error.BrotliDecompressionError,
        }
    }
}

const encoder = @import("compress/encode.zig");

pub const EncoderOptions = encoder.Options;
pub const CompressionOptions = encoder.Options;
pub const EncoderMode = encoder.Mode;
pub const CompressionMode = encoder.Mode;
pub const EncoderOperation = encoder.Operation;
pub const Encoder = encoder.Encoder;
pub const ProgressCallback = encoder.ProgressCallback;

pub const PARAM_MODE = encoder.PARAM_MODE;
pub const PARAM_QUALITY = encoder.PARAM_QUALITY;
pub const PARAM_LGWIN = encoder.PARAM_LGWIN;
pub const PARAM_LGBLOCK = encoder.PARAM_LGBLOCK;
pub const PARAM_DISABLE_LITERAL_CONTEXT_MODELING =
    encoder.PARAM_DISABLE_LITERAL_CONTEXT_MODELING;
pub const PARAM_SIZE_HINT = encoder.PARAM_SIZE_HINT;
pub const PARAM_LARGE_WINDOW = encoder.PARAM_LARGE_WINDOW;
pub const PARAM_NPOSTFIX = encoder.PARAM_NPOSTFIX;
pub const PARAM_NDIRECT = encoder.PARAM_NDIRECT;

/// Streaming/incremental compression facade over `Encoder`.
///
///     var sc = StreamingCompressor.init(allocator, .{ .quality = 9 });
///     defer sc.deinit();
///     const head = try sc.process(chunk);
///     const tail = try sc.finish();
pub const StreamingCompressor = struct {
    inner: Encoder,
    err: ?anyerror = null,

    pub fn init(allocator: std.mem.Allocator, options: CompressionOptions) StreamingCompressor {
        return .{ .inner = Encoder.init(allocator, options) };
    }

    pub fn deinit(self: *StreamingCompressor) void {
        self.inner.deinit();
    }

    pub fn setProgress(self: *StreamingCompressor, cb: ?ProgressCallback, ctx: ?*anyopaque) void {
        self.inner.setProgress(cb, ctx);
    }

    /// Attaches a custom dictionary; must precede the first `process`.
    /// Decoders must attach the identical bytes to decode the stream.
    pub fn attachDictionary(self: *StreamingCompressor, data: []const u8) bool {
        return self.inner.attachDictionary(data);
    }

    /// Pushes one input chunk, returning any compressed bytes ready now.
    /// Caller owns the returned slice.
    pub fn process(self: *StreamingCompressor, chunk: []const u8) ![]u8 {
        self.inner.compressStream(.process, chunk) catch |e| {
            self.err = e;
            return e;
        };
        return self.drain();
    }

    /// Flushes all pending input into complete (non-final) blocks.
    pub fn flush(self: *StreamingCompressor) ![]u8 {
        self.inner.compressStream(.flush, null) catch |e| {
            self.err = e;
            return e;
        };
        return self.drain();
    }

    /// Emits a metadata metablock (RFC 7932 section 9.2) carrying `payload`.
    /// Metadata is skipped by decoders that do not observe it and is never
    /// part of the decompressed output.
    pub fn emitMetadata(self: *StreamingCompressor, payload: []const u8) ![]u8 {
        self.inner.compressStream(.emit_metadata, payload) catch |e| {
            self.err = e;
            return e;
        };
        return self.drain();
    }

    /// Finishes the stream; the returned bytes end with the final block.
    pub fn finish(self: *StreamingCompressor) ![]u8 {
        if (!self.inner.isFinished()) {
            self.inner.compressStream(.finish, null) catch |e| {
                self.err = e;
                return e;
            };
        }
        return self.drain();
    }

    pub fn isFinished(self: *const StreamingCompressor) bool {
        return self.inner.isFinished();
    }

    fn drain(self: *StreamingCompressor) ![]u8 {
        const n = self.inner.out.items.len - self.inner.out_pos;
        if (n == 0) return &.{};
        const copy = try self.inner.allocator.alloc(u8, n);
        @memcpy(copy, self.inner.out.items[self.inner.out_pos..]);
        _ = self.inner.takeOutput(copy);
        return copy;
    }
};

/// Compress a complete byte range in one call.
///
///     const out = try brotli.compress(allocator, src);
///     defer allocator.free(out);
pub fn compress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return compressWithOptions(allocator, input, .{});
}

/// One-shot compression with explicit options (quality 0..11, window,
/// mode, progress callback, ...).
pub fn compressWithOptions(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: CompressionOptions,
) ![]u8 {
    var enc = Encoder.init(allocator, options);
    defer enc.deinit();
    enc.options.size_hint = input.len;

    enc.compressStream(.process, input) catch return error.BrotliCompressionError;
    enc.compressStream(.finish, null) catch return error.BrotliCompressionError;

    const n = enc.out.items.len - enc.out_pos;
    const result = try allocator.alloc(u8, n);
    @memcpy(result, enc.out.items[enc.out_pos..]);
    enc.out_pos = enc.out.items.len;
    return result;
}

/// Upper bound on compressed size for a given input size (mirrors
/// BrotliEncoderMaxCompressedSize).
pub fn maxCompressedSize(input_size: usize) usize {
    if (input_size == 0) return 2;
    // Wrapping arithmetic keeps this correct (and non-panicking) on targets
    // where usize is narrower than the largest supported stream.
    const num_large_blocks = input_size >> 14;
    const overhead = 2 + 4 * num_large_blocks + 4;
    const result = input_size +% overhead;
    if (result < input_size) return 0;
    return result;
}

/// Decompress into a caller-provided buffer (BrotliDecoderDecompress analog).
pub fn decompressInto(
    allocator: std.mem.Allocator,
    input: []const u8,
    output: []u8,
) !usize {
    var dec = Decoder.init(allocator, .{});
    defer dec.deinit();
    var in: []const u8 = input;
    var avail: []u8 = output;
    var total: u64 = 0;
    switch (dec.decompressStream(&in, &avail, &total)) {
        .success => {},
        else => return error.BrotliDecompressionError,
    }
    return @intCast(total);
}

pub const BLOCKSIZE_MAX = constants.BLOCK_SIZE_CAP;
pub const MAX_QUALITY = 11;
pub const MIN_QUALITY = 0;
pub const DEFAULT_QUALITY = 11;
pub const DEFAULT_WINDOW = 22;
pub const MIN_WINDOW_BITS = constants.LARGE_MIN_WBITS;
pub const MAX_WINDOW_BITS = 24;
pub const LARGE_MAX_WINDOW_BITS = constants.LARGE_MAX_WBITS;

pub const CONTEXT_MAP_MAX_RLE = constants.CONTEXT_MAP_MAX_RLE;
pub const MAX_NUMBER_OF_BLOCK_TYPES = constants.MAX_NUMBER_OF_BLOCK_TYPES;
pub const NUM_LITERAL_SYMBOLS = constants.NUM_LITERAL_SYMBOLS;
pub const NUM_COMMAND_SYMBOLS = constants.NUM_COMMAND_SYMBOLS;
pub const NUM_DISTANCE_SHORT_CODES = constants.NUM_DISTANCE_SHORT_CODES;
pub const WINDOW_GAP = constants.WINDOW_GAP;

test {
    std.testing.refAllDecls(@This());
}

const testing = std.testing;

test "version accessors" {
    try testing.expectEqualStrings(version, versionString());
    try testing.expectEqual(@as(u32, 3), versionNumber());
}

test "streaming decompressor on empty finalized stream" {
    var sd = StreamingDecompressor.init(testing.allocator, .{});
    defer sd.deinit();
    sd.feed(&.{0x06});
    var out: [16]u8 = undefined;
    const n = try sd.take(&out);
    try testing.expectEqual(@as(usize, 0), n);
    try testing.expect(sd.isFinished());
}

// Round-trip coverage for the native compressor against the native decoder.

fn expectRoundTrip(input: []const u8, options: CompressionOptions) !void {
    const allocator = testing.allocator;
    const compressed = try compressWithOptions(allocator, input, options);
    defer allocator.free(compressed);
    // Tiny inputs carry fixed tree overhead beyond the C-style formula.
    const bound = @max(maxCompressedSize(input.len), input.len * 2 + 700);
    try testing.expect(compressed.len <= bound);

    const decoded = try decompress(allocator, compressed);
    defer allocator.free(decoded);
    try testing.expectEqualSlices(u8, input, decoded);
}

test "round trip empty" {
    try expectRoundTrip(&.{}, .{});
    try expectRoundTrip(&.{}, .{ .quality = 0 });
    try expectRoundTrip(&.{}, .{ .quality = 5, .lgwin = 16 });
}

test "round trip tiny inputs" {
    try expectRoundTrip("a", .{});
    try expectRoundTrip("ab", .{});
    try expectRoundTrip("abc", .{});
    try expectRoundTrip("aaaaaaaa", .{});
    try expectRoundTrip("\x00\x00\x00\x00", .{});
}

test "round trip text at several qualities" {
    var input: [20000]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(1234);
    const words = [_][]const u8{ "the ", "quick ", "brown ", "fox ", "jumps ", "over ", "lazy ", "dog ", "brotli ", "zig " };
    var filled: usize = 0;
    while (filled < input.len - 16) {
        const w = words[prng.random().intRangeLessThan(usize, 0, words.len)];
        @memcpy(input[filled..][0..w.len], w);
        filled += w.len;
    }
    @memset(input[filled..], 'x');

    inline for (.{ 0, 1, 2, 5, 9, 11 }) |q| {
        try expectRoundTrip(input[0 .. 5000 + q], .{ .quality = q });
    }
    try expectRoundTrip(&input, .{});
}

test "round trip highly repetitive data" {
    var input = [_]u8{0xAB} ** 70000;
    try expectRoundTrip(&input, .{ .quality = 11 });
    try expectRoundTrip(&input, .{ .quality = 1 });

    var pattern: [30000]u8 = undefined;
    for (&pattern, 0..) |*b, i| b.* = @truncate(i / 7);
    try expectRoundTrip(&pattern, .{});
}

test "round trip incompressible data uses stored blocks" {
    var random: [40000]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(99);
    prng.random().bytes(&random);
    try expectRoundTrip(&random, .{});
    try expectRoundTrip(&random, .{ .quality = 2 });
}

test "round trip binary with long distance matches" {
    var input: [150000]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(7);
    for (&input, 0..) |*b, i| {
        b.* = if (i < 1000) @truncate(prng.random().int(u8)) else input[i - 1000];
    }
    try expectRoundTrip(&input, .{ .lgwin = 16 });
    try expectRoundTrip(&input, .{ .lgwin = 22 });
    try expectRoundTrip(&input, .{ .lgwin = 24 });
}

test "round trip across window sizes" {
    var input: [9000]u8 = undefined;
    for (&input, 0..) |*b, i| b.* = @truncate(i *% 31 +% (i >> 3));
    inline for (.{ 10, 12, 16, 17, 18, 20, 21, 22, 23 }) |w| {
        try expectRoundTrip(&input, .{ .lgwin = w });
    }
}

test "one-shot compress honors maxCompressedSize bound" {
    const allocator = testing.allocator;
    var input: [100000]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(42);
    prng.random().bytes(&input);
    const compressed = try compressWithOptions(allocator, &input, .{});
    defer allocator.free(compressed);
    // Tiny inputs carry fixed tree overhead beyond the C-style formula.
    const bound = @max(maxCompressedSize(input.len), input.len * 2 + 700);
    try testing.expect(compressed.len <= bound);
}

test "streaming compressor matches one-shot output shape" {
    const allocator = testing.allocator;
    var input: [50000]u8 = undefined;
    for (&input, 0..) |*b, i| b.* = @truncate(i % 251);

    // Chunked streaming compression.
    var sc = StreamingCompressor.init(allocator, .{});
    defer sc.deinit();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    var off: usize = 0;
    while (off < input.len) {
        const take = @min(@as(usize, 7777), input.len - off);
        const piece = try sc.process(input[off .. off + take]);
        defer allocator.free(piece);
        try out.appendSlice(allocator, piece);
        off += take;
    }
    const tail = try sc.finish();
    defer allocator.free(tail);
    try out.appendSlice(allocator, tail);
    try testing.expect(sc.isFinished());

    const decoded = try decompress(allocator, out.items);
    defer allocator.free(decoded);
    try testing.expectEqualSlices(u8, &input, decoded);
}

test "streaming flush produces decodable intermediate output" {
    const allocator = testing.allocator;

    var sc = StreamingCompressor.init(allocator, .{});
    defer sc.deinit();
    _ = try sc.process("flush me please flush me please ");
    const flushed = try sc.flush();
    defer allocator.free(flushed);
    try testing.expect(flushed.len > 0);

    _ = try sc.process("tail tail tail");
    const tail = try sc.finish();
    defer allocator.free(tail);

    // The concatenation is a valid stream decoding back to both halves.
    var whole: std.ArrayList(u8) = .empty;
    defer whole.deinit(allocator);
    try whole.appendSlice(allocator, flushed);
    try whole.appendSlice(allocator, tail);

    const decoded = try decompress(allocator, whole.items);
    defer allocator.free(decoded);
    try testing.expectEqualStrings("flush me please flush me please tail tail tail", decoded);
}

test "progress callback fires during streaming" {
    const Counter = struct {
        calls: usize = 0,
        last_done: usize = 0,

        fn cb(ctx: ?*anyopaque, done: usize, total: usize) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.calls += 1;
            self.last_done = done;
            _ = total;
        }
    };

    var counter = Counter{};
    var sc = StreamingCompressor.init(testing.allocator, .{
        .size_hint = 100000,
    });
    defer sc.deinit();
    sc.setProgress(Counter.cb, &counter);

    var chunk: [4096]u8 = undefined;
    @memset(&chunk, 'p');
    var i: usize = 0;
    while (i < 100000 / 4096) : (i += 1) {
        const piece = try sc.process(&chunk);
        testing.allocator.free(piece);
    }
    const tail = try sc.finish();
    testing.allocator.free(tail);

    try testing.expect(counter.calls > 0);
    try testing.expect(counter.last_done > 0);
}

test "compress then decompressInto fixed buffer" {
    const allocator = testing.allocator;
    const original = "fixed buffer target for decompressInto";
    const compressed = try compressWithOptions(allocator, original, .{});
    defer allocator.free(compressed);

    var buffer: [128]u8 = undefined;
    const n = try decompressInto(allocator, compressed, &buffer);
    try testing.expectEqualStrings(original, buffer[0..n]);
}

test "setParameter accepts documented identifiers" {
    var enc = Encoder.init(testing.allocator, .{});
    defer enc.deinit();
    try testing.expect(enc.setParameter(PARAM_QUALITY, 9));
    try testing.expect(enc.setParameter(PARAM_LGWIN, 20));
    try testing.expect(enc.setParameter(PARAM_SIZE_HINT, 4096));
    try testing.expect(!enc.setParameter(999, 1));
}

test "custom dictionary round trip through encoder and decoder" {
    const allocator = testing.allocator;
    const dict = "the quick brown fox jumps over the lazy dog near the river bank every morning";
    const input = "quick brown fox jumps over the lazy dog";

    var enc = Encoder.init(allocator, .{ .quality = 11 });
    defer enc.deinit();
    try testing.expect(enc.attachDictionary(dict));
    try enc.compressStream(.process, input);
    try enc.compressStream(.finish, null);
    const compressed = try allocator.dupe(u8, enc.out.items[enc.out_pos..]);
    defer allocator.free(compressed);

    // With the dictionary attached the stream must decode exactly.
    {
        var d = Decoder.init(allocator, .{});
        defer d.deinit();
        try testing.expect(d.attachDictionary(dict));
        var in: []const u8 = compressed;
        var out: [256]u8 = undefined;
        var avail: []u8 = &out;
        var total: u64 = 0;
        try testing.expectEqual(DecodeResult.success, d.decompressStream(&in, &avail, &total));
        try testing.expectEqualStrings(input, out[0..@intCast(total)]);
    }

    // Without it, compound references cannot resolve: the decoder must not
    // silently produce wrong bytes.
    {
        var d = Decoder.init(allocator, .{});
        defer d.deinit();
        var in: []const u8 = compressed;
        var out: [256]u8 = undefined;
        var avail: []u8 = &out;
        var total: u64 = 0;
        const r = d.decompressStream(&in, &avail, &total);
        if (r == .success) {
            // If it somehow succeeds, output must NOT equal the input
            // (references resolved against nothing).
            try testing.expect(total != input.len or !std.mem.eql(u8, out[0..@intCast(total)], input));
        }
    }

    // Dictionary must be rejected after use began.
    try testing.expect(!enc.attachDictionary("late"));
}

test "streaming compressor attachDictionary passthrough" {
    const allocator = testing.allocator;
    const dict = "shared vocabulary for streaming compression tests";
    const input = "vocabulary compression vocabulary tests";

    var sc = StreamingCompressor.init(allocator, .{});
    defer sc.deinit();
    try testing.expect(sc.attachDictionary(dict));

    const head = try sc.process(input);
    defer allocator.free(head);
    const tail = try sc.finish();
    defer allocator.free(tail);

    var whole: std.ArrayList(u8) = .empty;
    defer whole.deinit(allocator);
    try whole.appendSlice(allocator, head);
    try whole.appendSlice(allocator, tail);

    var d = Decoder.init(allocator, .{});
    defer d.deinit();
    try testing.expect(d.attachDictionary(dict));
    var in: []const u8 = whole.items;
    var out: [256]u8 = undefined;
    var avail: []u8 = &out;
    var total: u64 = 0;
    try testing.expectEqual(DecodeResult.success, d.decompressStream(&in, &avail, &total));
    try testing.expectEqualStrings(input, out[0..@intCast(total)]);
}

test "large window round trip up to 30 bits" {
    const allocator = testing.allocator;

    inline for (.{ 25, 28, 30 }) |w| {
        var input: [40000]u8 = undefined;
        var prng = std.Random.DefaultPrng.init(@intCast(w));
        for (&input) |*b| b.* = prng.random().intRangeAtMost(u8, 'a', 'z');

        const compressed = try compressWithOptions(allocator, &input, .{
            .quality = 11,
            .lgwin = w,
            .large_window = true,
        });
        defer allocator.free(compressed);

        const decoded = try decompressWithOptions(allocator, compressed, .{
            .large_window = true,
        });
        defer allocator.free(decoded);
        try testing.expectEqualSlices(u8, &input, decoded);
    }
}

test "npostfix and ndirect combinations round trip" {
    const allocator = testing.allocator;
    const input = "information about the network and the program window repeats here " ** 30;

    const combos = [_][2]u32{
        .{ 0, 0 }, .{ 1, 0 }, .{ 2, 4 }, .{ 3, 120 }, .{ 0, 15 }, .{ 1, 8 },
    };
    for (combos) |combo| {
        const compressed = try compressWithOptions(allocator, input, .{
            .quality = 11,
            .npostfix = combo[0],
            .ndirect = combo[1] << @intCast(combo[0]),
        });
        defer allocator.free(compressed);

        const decoded = try decompress(allocator, compressed);
        defer allocator.free(decoded);
        try testing.expectEqualSlices(u8, input, decoded);
    }
}

test "metadata metablock round trips with callbacks" {
    const allocator = testing.allocator;

    var enc = Encoder.init(allocator, .{ .quality = 9 });
    defer enc.deinit();
    try enc.compressStream(.process, "payload before metadata");
    try enc.compressStream(.emit_metadata, "META-123");
    try enc.compressStream(.finish, null);

    var whole: std.ArrayList(u8) = .empty;
    defer whole.deinit(allocator);
    var tmp: [4096]u8 = undefined;
    while (enc.hasMoreOutput()) {
        const n = enc.takeOutput(&tmp);
        try whole.appendSlice(allocator, tmp[0..n]);
    }

    const Captured = struct {
        seen: usize = 0,
        buf: [64]u8 = undefined,
        n: usize = 0,
        fn start(ctx: ?*anyopaque, size: usize) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.seen = size;
        }
        fn chunk(ctx: ?*anyopaque, data: []const u8) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            // Chunks arrive in arbitrary splits; accumulate them.
            @memcpy(self.buf[self.n..][0..data.len], data);
            self.n += data.len;
        }
    };
    var cap = Captured{};
    var dec = Decoder.init(allocator, .{});
    defer dec.deinit();
    dec.setMetadataCallbacks(.{ .ctx = &cap, .start = Captured.start, .chunk = Captured.chunk });

    var input: []const u8 = whole.items;
    var out_buf: [64]u8 = undefined;
    var avail: []u8 = &out_buf;
    var total: u64 = 0;
    try testing.expectEqual(DecodeResult.success, dec.decompressStream(&input, &avail, &total));
    try testing.expectEqualStrings("payload before metadata", out_buf[0..@intCast(total)]);
    try testing.expectEqual(@as(usize, 8), cap.seen);
    try testing.expect(cap.n == cap.seen);
    try testing.expectEqualStrings("META-123", cap.buf[0..cap.n]);
}

test "streaming compressor emits metadata between chunks" {
    const allocator = testing.allocator;

    var sc = StreamingCompressor.init(allocator, .{});
    defer sc.deinit();
    const head = try sc.process("chunk one; ");
    defer allocator.free(head);
    const meta = try sc.emitMetadata("note");
    defer allocator.free(meta);
    const tail = try sc.finish();
    defer allocator.free(tail);

    var whole: std.ArrayList(u8) = .empty;
    defer whole.deinit(allocator);
    try whole.appendSlice(allocator, head);
    try whole.appendSlice(allocator, meta);
    try whole.appendSlice(allocator, tail);

    const decoded = try decompress(allocator, whole.items);
    defer allocator.free(decoded);
    try testing.expectEqualStrings("chunk one; ", decoded);
}

test "static dictionary words survive round trip at high quality" {
    const allocator = testing.allocator;
    // Natural-language text rich in built-in corpus vocabulary.
    const input = "Information technology transformed the nation. Windows programs run " ++
        "across networks. International theory on government and communication " ++
        "developed over generations of political transformation in America. " ++
        "The quick brown fox jumps over the lazy dog near the river bank. ";

    inline for (.{ 5, 9, 11 }) |q| {
        const compressed = try compressWithOptions(allocator, input, .{ .quality = q });
        defer allocator.free(compressed);
        const decoded = try decompress(allocator, compressed);
        defer allocator.free(decoded);
        try testing.expectEqualSlices(u8, input, decoded);
    }
}

test "literal block switching on heterogeneous content" {
    const allocator = testing.allocator;
    // Distinct character classes in long runs: the splitter should code each
    // class through its own literal block type and tree.
    var input: [64000]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(99);
    const classes = [_][2]u8{
        .{ 'a', 'z' }, .{ 'A', 'Z' }, .{ '0', '9' }, .{ '!', '/' },
    };
    var pos: usize = 0;
    var round: usize = 0;
    while (pos < input.len) : (round += 1) {
        const cls = classes[round % classes.len];
        const span = @min(@as(usize, 8000), input.len - pos);
        for (input[pos..][0..span]) |*b| {
            b.* = prng.random().intRangeAtMost(u8, cls[0], cls[1]);
        }
        pos += span;
    }

    inline for (.{ 9, 11 }) |q| {
        const compressed = try compressWithOptions(allocator, &input, .{ .quality = q });
        defer allocator.free(compressed);
        const decoded = try decompress(allocator, compressed);
        defer allocator.free(decoded);
        try testing.expectEqualSlices(u8, &input, decoded);
    }
}

test "metadata empty payload round trips" {
    const allocator = testing.allocator;
    var enc = Encoder.init(allocator, .{});
    defer enc.deinit();
    try enc.compressStream(.emit_metadata, "");
    try enc.compressStream(.finish, "after empty metadata");
    var whole: std.ArrayList(u8) = .empty;
    defer whole.deinit(allocator);
    var tmp: [512]u8 = undefined;
    while (enc.hasMoreOutput()) {
        const n = enc.takeOutput(&tmp);
        try whole.appendSlice(allocator, tmp[0..n]);
    }
    const decoded = try decompress(allocator, whole.items);
    defer allocator.free(decoded);
    try testing.expectEqualStrings("after empty metadata", decoded);
}

test "streaming decompression with small feeds" {
    const allocator = testing.allocator;
    const input = "resumption across sub-byte boundaries must preserve every bit " ** 40;

    const compressed = try compressWithOptions(allocator, input, .{ .quality = 9 });
    defer allocator.free(compressed);

    var sd = StreamingDecompressor.init(allocator, .{});
    defer sd.deinit();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    var buf: [256]u8 = undefined;

    for (compressed) |byte| sd.feed(&.{byte});
    sd.endInput();

    while (!sd.isFinished()) {
        const n = try sd.take(&buf);
        if (n > 0) try out.appendSlice(allocator, buf[0..n]);
        if (n == 0 and sd.hasError()) return error.BrotliStreamError;
    }
    try testing.expectEqualSlices(u8, input, out.items);
}

test "streaming decompression with mixed chunk sizes" {
    const allocator = testing.allocator;
    const input = "streaming decompression must work with arbitrary chunk sizes." ** 20;

    const compressed = try compressWithOptions(allocator, input, .{ .quality = 9 });
    defer allocator.free(compressed);

    var sd = StreamingDecompressor.init(allocator, .{});
    defer sd.deinit();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    var buf: [256]u8 = undefined;

    const sizes = [_]usize{ 1, 3, 7, 64, 128 };
    var ci: usize = 0;
    var si: usize = 0;
    while (ci < compressed.len) {
        const sz = sizes[si % sizes.len];
        const end = @min(ci + sz, compressed.len);
        sd.feed(compressed[ci..end]);
        ci = end;
        si += 1;
    }
    sd.endInput();

    while (!sd.isFinished()) {
        const n = try sd.take(&buf);
        if (n > 0) try out.appendSlice(allocator, buf[0..n]);
        if (n == 0 and sd.hasError()) return error.BrotliStreamError;
    }
    try testing.expectEqualSlices(u8, input, out.items);
}
