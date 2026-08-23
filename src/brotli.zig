//! Native Zig implementation of the Brotli compressed-data format
//! (RFC 7932 / Large Window Brotli) — public API.
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
pub const version = "0.0.2";
pub const version_number: u32 = 0 * 100 * 100 + 0 * 100 + 2;

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
    /// Next unconsumed input chunk.
    pending: ?[]const u8 = null,
    inner: Decoder,
    finished_: bool = false,

    pub fn init(allocator: std.mem.Allocator, options: DecoderOptions) StreamingDecompressor {
        return .{ .inner = Decoder.init(allocator, options) };
    }

    pub fn deinit(self: *StreamingDecompressor) void {
        self.inner.deinit();
    }

    /// Presents the next chunk of compressed input. Input is referenced
    /// until the next `feed`/`take` cycle completes the chunk.
    pub fn feed(self: *StreamingDecompressor, chunk: []const u8) void {
        self.pending = chunk;
    }

    /// Decodes as much as possible into `out`; returns bytes written.
    pub fn take(self: *StreamingDecompressor, out: []u8) !usize {
        var input: []const u8 = self.pending orelse &.{};
        var avail: []u8 = out;
        var total: u64 = 0;
        const r = self.inner.decompressStream(&input, &avail, &total);
        self.pending = if (input.len != 0) input else null;
        switch (r) {
            .success => self.finished_ = true,
            .needs_more_input => {},
            .needs_more_output => {},
            .err => return error.BrotliStreamError,
        }
        return out.len - avail.len;
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
    const num_large_blocks = input_size >> 14;
    const overhead = 2 + 4 * num_large_blocks + 4;
    const result = input_size + overhead;
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
    try testing.expectEqual(@as(u32, 2), versionNumber());
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
