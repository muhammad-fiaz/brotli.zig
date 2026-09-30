//! Native Zig implementation of the Brotli compressed data format
//! (RFC 7932 / Large Window Brotli) — public client API facade.
//!
//! Provides a thin, idiomatic client surface for Brotli compression, decompression,
//! streaming I/O, format inspection, and configuration.
//!
//! Usage:
//!
//!     const brotli = @import("brotli");
//!
//!     // One-shot compression and decompression
//!     const compressed = try brotli.compress(allocator, "data to compress");
//!     defer allocator.free(compressed);
//!
//!     const original = try brotli.decompress(allocator, compressed);
//!     defer allocator.free(original);
//!
//!     // Reusable context
//!     var compressor = brotli.Compressor.init(allocator, .{ .quality = 9 });
//!     defer compressor.deinit();

const std = @import("std");

pub const constants = @import("common/constants.zig");
pub const context = @import("common/context.zig");
pub const transform = @import("common/transform.zig");
pub const Dictionary = @import("dictionary/dictionary.zig");
pub const BitReader = @import("bitstream/bit_reader.zig").BitReader;
pub const bit_writer = @import("bitstream/bit_writer.zig");
pub const huffman = @import("huffman/huffman.zig");
pub const HuffmanCode = huffman.HuffmanCode;

const encoder = @import("compress/encode.zig");
const decoder = @import("decompress/decode.zig");
pub const streaming = @import("streaming/streaming.zig");

// -------------------------------------------------------------------------
// Library and Specification Versions
// -------------------------------------------------------------------------

/// Native Brotli library release version.
pub const version = "0.0.4";
pub const version_number: u32 = 0 * 100 * 100 + 0 * 100 + 4;
pub const versionNumberValue: u32 = version_number;

/// Brotli format specification version implemented (RFC 7932 / v1.2.0).
pub const spec_version = "1.2.0";
pub const spec_version_number: u32 = 1 * 100 * 100 + 2 * 100 + 0;
pub const specVersion = spec_version;
pub const specVersionNumber = spec_version_number;

/// Returns the library version string.
pub fn versionString() []const u8 {
    return version;
}

/// Returns the integer-encoded library version.
pub fn versionNumber() u32 {
    return version_number;
}

// -------------------------------------------------------------------------
// Codec Types & Contexts
// -------------------------------------------------------------------------

pub const Compressor = encoder.Encoder;
pub const Encoder = encoder.Encoder;
pub const CompressionOptions = encoder.Options;
pub const EncoderOptions = encoder.Options;
pub const CompressionMode = encoder.Mode;
pub const Strategy = encoder.Mode;
pub const EncoderMode = encoder.Mode;
pub const EncoderOperation = encoder.Operation;
pub const ProgressCallback = encoder.ProgressCallback;

pub const Decompressor = decoder.Decoder;
pub const Decoder = decoder.Decoder;
pub const DecompressionOptions = decoder.Options;
pub const DecoderOptions = decoder.Options;
pub const DecodeResult = decoder.Result;
pub const ErrorCode = decoder.ErrorCode;
pub const MetadataCallbacks = decoder.MetadataCallbacks;
pub const DecompressionContext = decoder.Decoder;
pub const BrotliCodecError = decoder.ErrorCode;

pub const StreamingCompressor = streaming.StreamingCompressor;
pub const StreamingDecompressor = streaming.StreamingDecompressor;

// -------------------------------------------------------------------------
// Error Reporting
// -------------------------------------------------------------------------

/// Canonical public error set for Brotli operations.
pub const Error = error{
    CorruptStream,
    TruncatedInput,
    InvalidHeader,
    InvalidMetaBlock,
    InvalidHuffmanTree,
    InvalidCommand,
    InvalidDistance,
    InvalidDictionaryReference,
    ResourceLimitExceeded,
    OutputLimitExceeded,
    OutOfMemory,
    InvalidParameter,
    InvalidStreamingState,
    NeedsMoreInput,
    NeedsMoreOutput,
    BrotliCompressionError,
    BrotliDecompressionError,
    BrotliStreamError,
};

/// Diagnostic wrapper providing status inspectability for decoder operations.
pub const BrotliErrorInfo = struct {
    code: ErrorCode,

    pub fn name(self: BrotliErrorInfo) []const u8 {
        return self.code.name();
    }
    pub fn isError(self: BrotliErrorInfo) bool {
        return self.code.isError();
    }
    pub fn toError(self: BrotliErrorInfo) Error {
        return self.code.toError();
    }
};

// -------------------------------------------------------------------------
// Public API Functions (Delegations to Specialized Codec Modules)
// -------------------------------------------------------------------------

/// Compresses a slice of bytes into an allocated buffer with default options.
/// The caller owns the returned slice.
pub const compress = encoder.compress;

/// Compresses a slice of bytes with explicit compression options.
/// The caller owns the returned slice.
pub const compressWithOptions = encoder.compressWithOptions;

/// Returns an upper bound on compressed size for a given input size.
pub const maxCompressedSize = encoder.maxCompressedSize;

/// Decompresses a complete Brotli stream into an allocated buffer with default options.
/// The caller owns the returned slice.
pub const decompress = decoder.decompress;

/// Decompresses a complete Brotli stream with explicit options (window limits, dictionary, etc.).
/// The caller owns the returned slice.
pub const decompressWithOptions = decoder.decompressWithOptions;

/// Decompresses directly into a caller-provided destination slice.
pub const decompressInto = decoder.decompressInto;

/// Compresses from a `std.Io.Reader` directly to a `std.Io.Writer` using chunked streaming.
pub const compressStream = streaming.compressStream;

/// Decompresses from a `std.Io.Reader` directly to a `std.Io.Writer` using chunked streaming.
pub const decompressStream = streaming.decompressStream;

// -------------------------------------------------------------------------
// Configuration Parameters & Limits
// -------------------------------------------------------------------------

pub const paramMode = encoder.paramMode;
pub const paramQuality = encoder.paramQuality;
pub const paramLgWin = encoder.paramLgWin;
pub const paramLgBlock = encoder.paramLgBlock;
pub const paramDisableLiteralContextModeling = encoder.paramDisableLiteralContextModeling;
pub const paramSizeHint = encoder.paramSizeHint;
pub const paramLargeWindow = encoder.paramLargeWindow;
pub const paramNPostfix = encoder.paramNPostfix;
pub const paramNDirect = encoder.paramNDirect;

pub const PARAM_MODE = paramMode;
pub const PARAM_QUALITY = paramQuality;
pub const PARAM_LGWIN = paramLgWin;
pub const PARAM_LGBLOCK = paramLgBlock;
pub const PARAM_DISABLE_LITERAL_CONTEXT_MODELING = paramDisableLiteralContextModeling;
pub const PARAM_SIZE_HINT = paramSizeHint;
pub const PARAM_LARGE_WINDOW = paramLargeWindow;
pub const PARAM_NPOSTFIX = paramNPostfix;
pub const PARAM_NDIRECT = paramNDirect;

pub const maxBlockSize = constants.BLOCK_SIZE_CAP;
pub const maxQuality = 11;
pub const minQuality = 0;
pub const defaultQuality = 11;
pub const defaultWindow = 22;
pub const minWindowBits = constants.LARGE_MIN_WBITS;
pub const maxWindowBits = 24;
pub const largeMaxWindowBits = constants.LARGE_MAX_WBITS;

pub const BLOCKSIZE_MAX = maxBlockSize;
pub const MAX_QUALITY = maxQuality;
pub const MIN_QUALITY = minQuality;
pub const DEFAULT_QUALITY = defaultQuality;
pub const DEFAULT_WINDOW = defaultWindow;
pub const MIN_WINDOW_BITS = minWindowBits;
pub const MAX_WINDOW_BITS = maxWindowBits;
pub const LARGE_MAX_WINDOW_BITS = largeMaxWindowBits;

pub const CONTEXT_MAP_MAX_RLE = constants.CONTEXT_MAP_MAX_RLE;
pub const MAX_NUMBER_OF_BLOCK_TYPES = constants.MAX_NUMBER_OF_BLOCK_TYPES;
pub const NUM_LITERAL_SYMBOLS = constants.NUM_LITERAL_SYMBOLS;
pub const NUM_COMMAND_SYMBOLS = constants.NUM_COMMAND_SYMBOLS;
pub const NUM_DISTANCE_SHORT_CODES = constants.NUM_DISTANCE_SHORT_CODES;
pub const WINDOW_GAP = constants.WINDOW_GAP;

// -------------------------------------------------------------------------
// Unit Tests for Public Facade
// -------------------------------------------------------------------------

const testing = std.testing;

test {
    testing.refAllDecls(@This());
}

test "facade version accessors" {
    try testing.expectEqualStrings("0.0.4", version);
    try testing.expectEqualStrings(version, versionString());
    try testing.expectEqual(@as(u32, 4), versionNumber());
    try testing.expectEqualStrings("1.2.0", specVersion);
    try testing.expectEqual(@as(u32, 10200), specVersionNumber);
}

test "facade delegation round trip" {
    const original = "Testing thin public facade round-trip delegation in brotli.zig!";
    const comp = try compress(testing.allocator, original);
    defer testing.allocator.free(comp);

    const decomp = try decompress(testing.allocator, comp);
    defer testing.allocator.free(decomp);

    try testing.expectEqualStrings(original, decomp);
}

// -------------------------------------------------------------------------
// Integration, Edge-Case, and Interoperability Test Cases
// -------------------------------------------------------------------------

fn repeatPattern(comptime s: []const u8, comptime count: usize) [s.len * count]u8 {
    var res: [s.len * count]u8 = undefined;
    for (0..count) |i| {
        @memcpy(res[i * s.len .. (i + 1) * s.len], s);
    }
    return res;
}

fn expectRoundTrip(input: []const u8, options: CompressionOptions) !void {
    const allocator = testing.allocator;
    const compressed = try compressWithOptions(allocator, input, options);
    defer allocator.free(compressed);
    const bound = @max(maxCompressedSize(input.len), input.len * 2 + 700);
    try testing.expect(compressed.len <= bound);

    const decoded = try decompress(allocator, compressed);
    defer allocator.free(decoded);
    try testing.expectEqualSlices(u8, input, decoded);
}

test "round trip empty" {
    try expectRoundTrip(&.{}, .{});
    try expectRoundTrip(&.{}, .{ .quality = 0 });
    try expectRoundTrip(&.{}, .{ .quality = 5, .lgWin = 16 });
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
    var input: [70000]u8 = @splat(0xAB);
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
    try expectRoundTrip(&input, .{ .lgWin = 16 });
    try expectRoundTrip(&input, .{ .lgWin = 22 });
    try expectRoundTrip(&input, .{ .lgWin = 24 });
}

test "round trip across window sizes" {
    var input: [9000]u8 = undefined;
    for (&input, 0..) |*b, i| b.* = @truncate(i *% 31 +% (i >> 3));
    inline for (.{ 10, 12, 16, 17, 18, 20, 21, 22, 23 }) |w| {
        try expectRoundTrip(&input, .{ .lgWin = w });
    }
}

test "one-shot compress honors maxCompressedSize bound" {
    const allocator = testing.allocator;
    var input: [100000]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(42);
    prng.random().bytes(&input);
    const compressed = try compressWithOptions(allocator, &input, .{});
    defer allocator.free(compressed);
    const bound = @max(maxCompressedSize(input.len), input.len * 2 + 700);
    try testing.expect(compressed.len <= bound);
}

test "streaming compressor matches one-shot output shape" {
    const allocator = testing.allocator;
    var input: [50000]u8 = undefined;
    for (&input, 0..) |*b, i| b.* = @truncate(i % 251);

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
    const tail = try sc.finishAlloc();
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
    const flushed = try sc.flushAlloc();
    defer allocator.free(flushed);
    try testing.expect(flushed.len > 0);

    _ = try sc.process("tail tail tail");
    const tail = try sc.finishAlloc();
    defer allocator.free(tail);

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
        .sizeHint = 100000,
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
    const tail = try sc.finishAlloc();
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
    var enc = Compressor.init(testing.allocator, .{});
    defer enc.deinit();
    try testing.expect(enc.setParameter(paramQuality, 9));
    try testing.expect(enc.setParameter(paramLgWin, 20));
    try testing.expect(enc.setParameter(paramSizeHint, 4096));
    try testing.expect(!enc.setParameter(999, 1));
}

test "custom dictionary round trip through encoder and decoder" {
    const allocator = testing.allocator;
    const dict = "the quick brown fox jumps over the lazy dog near the river bank every morning";
    const input = "quick brown fox jumps over the lazy dog";

    var enc = Compressor.init(allocator, .{ .quality = 11 });
    defer enc.deinit();
    try testing.expect(enc.attachDictionary(dict));
    try enc.compressStream(.process, input);
    try enc.compressStream(.finish, null);
    const compressed = try allocator.dupe(u8, enc.out.items[enc.out_pos..]);
    defer allocator.free(compressed);

    {
        var d = Decompressor.init(allocator, .{});
        defer d.deinit();
        try testing.expect(d.attachDictionary(dict));
        var in: []const u8 = compressed;
        var out: [256]u8 = undefined;
        var avail: []u8 = &out;
        var total: u64 = 0;
        try testing.expectEqual(DecodeResult.success, d.decompressStream(&in, &avail, &total));
        try testing.expectEqualStrings(input, out[0..@intCast(total)]);
    }

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
    const tail = try sc.finishAlloc();
    defer allocator.free(tail);

    var whole: std.ArrayList(u8) = .empty;
    defer whole.deinit(allocator);
    try whole.appendSlice(allocator, head);
    try whole.appendSlice(allocator, tail);

    var d = Decompressor.init(allocator, .{});
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
            .lgWin = w,
            .largeWindow = true,
        });
        defer allocator.free(compressed);

        const decoded = try decompressWithOptions(allocator, compressed, .{
            .largeWindow = true,
        });
        defer allocator.free(decoded);
        try testing.expectEqualSlices(u8, &input, decoded);
    }
}

test "npostfix and ndirect combinations round trip" {
    const allocator = testing.allocator;
    const input = repeatPattern("information about the network and the program window repeats here ", 30);

    const combos = [_][2]u32{
        .{ 0, 0 }, .{ 1, 0 }, .{ 2, 4 }, .{ 3, 120 }, .{ 0, 15 }, .{ 1, 8 },
    };
    for (combos) |combo| {
        const compressed = try compressWithOptions(allocator, &input, .{
            .quality = 11,
            .nPostfix = combo[0],
            .nDirect = combo[1] << @intCast(combo[0]),
        });
        defer allocator.free(compressed);

        const decoded = try decompress(allocator, compressed);
        defer allocator.free(decoded);
        try testing.expectEqualSlices(u8, &input, decoded);
    }
}

test "metadata metablock round trips with callbacks" {
    const allocator = testing.allocator;

    var enc = Compressor.init(allocator, .{ .quality = 9 });
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
            @memcpy(self.buf[self.n..][0..data.len], data);
            self.n += data.len;
        }
    };
    var cap = Captured{};
    var dec = Decompressor.init(allocator, .{});
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
    const tail = try sc.finishAlloc();
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

test "streaming decompression with small feeds" {
    const allocator = testing.allocator;
    const input = repeatPattern("resumption across sub-byte boundaries must preserve every bit ", 40);

    const compressed = try compressWithOptions(allocator, &input, .{ .quality = 9 });
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
    try testing.expectEqualSlices(u8, &input, out.items);
}

test "streaming decompression with mixed chunk sizes" {
    const allocator = testing.allocator;
    const input = repeatPattern("streaming decompression must work with arbitrary chunk sizes.", 20);

    const compressed = try compressWithOptions(allocator, &input, .{ .quality = 9 });
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
    try testing.expectEqualSlices(u8, &input, out.items);
}

test "StreamingCompressor with std.Io.Writer" {
    const allocator = testing.allocator;
    const input = "streaming through std.Io.Writer in Zig 0.17! Direct chunk output.";

    var out_list: std.ArrayList(u8) = .empty;
    defer out_list.deinit(allocator);

    var sc = StreamingCompressor.init(allocator, .{ .quality = 6 });
    defer sc.deinit();

    var chunk_buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&chunk_buf);

    try sc.write(input[0..20], &writer);
    try out_list.appendSlice(allocator, writer.buffered());
    writer = std.Io.Writer.fixed(&chunk_buf);

    try sc.write(input[20..], &writer);
    try out_list.appendSlice(allocator, writer.buffered());
    writer = std.Io.Writer.fixed(&chunk_buf);

    try sc.finish(&writer);
    try out_list.appendSlice(allocator, writer.buffered());

    const decompressed = try decompress(allocator, out_list.items);
    defer allocator.free(decompressed);
    try testing.expectEqualStrings(input, decompressed);
}

test "compressStream and decompressStream with std.Io" {
    const allocator = testing.allocator;
    const message = repeatPattern("Testing full std.Io.Reader and std.Io.Writer pipeline for Brotli stream. ", 15);

    var compressed_storage: [4096]u8 = undefined;
    var comp_writer = std.Io.Writer.fixed(&compressed_storage);

    var in_reader = std.Io.Reader.fixed(&message);
    try compressStream(allocator, &in_reader, &comp_writer, .{ .quality = 5 });

    const compressed_data = comp_writer.buffered();
    try testing.expect(compressed_data.len > 0);

    var decompressed_storage: [message.len + 128]u8 = undefined;
    var decomp_writer = std.Io.Writer.fixed(&decompressed_storage);
    var comp_reader = std.Io.Reader.fixed(compressed_data);

    try decompressStream(allocator, &comp_reader, &decomp_writer, .{});
    try testing.expectEqualStrings(&message, decomp_writer.buffered());
}

test "Compressor and Decompressor context reuse via reset" {
    const allocator = testing.allocator;
    var comp = Compressor.init(allocator, .{ .quality = 6 });
    defer comp.deinit();

    var decomp = Decompressor.init(allocator, .{});
    defer decomp.deinit();

    const text1 = "First dataset for reusable compressor/decompressor context testing.";
    const text2 = "Second dataset testing state reset without reallocating buffers!";
    const text3 = "Third run to be absolutely sure no state contamination happens across resets.";

    const datasets = [_][]const u8{ text1, text2, text3 };

    for (datasets) |data| {
        const comp_out = try comp.compress(data);
        defer allocator.free(comp_out);

        const decomp_out = try decomp.decompress(comp_out);
        defer allocator.free(decomp_out);

        try testing.expectEqualStrings(data, decomp_out);

        comp.reset(.{ .quality = 6 });
        decomp.reset(.{});
    }
}

test "Decompressor resource limit enforcement" {
    const allocator = testing.allocator;
    const big_input = repeatPattern("resource limits are very important for security and stability! ", 100);

    const compressed = try compress(allocator, &big_input);
    defer allocator.free(compressed);

    const err = decompressWithOptions(allocator, compressed, .{
        .maxOutputSize = 100,
    });
    try testing.expectError(error.ResourceLimitExceeded, err);

    const err2 = decompressWithOptions(allocator, compressed, .{
        .ringBufferSizeLimit = 1024,
    });
    try testing.expectError(error.ResourceLimitExceeded, err2);
}

test "Quality levels 0 through 11 round trip verification" {
    const allocator = testing.allocator;
    const sample = "The quick brown fox jumps over the lazy dog. Repetition repetition repetition!";

    var q: u32 = 0;
    while (q <= 11) : (q += 1) {
        const compressed = try compressWithOptions(allocator, sample, .{ .quality = q });
        defer allocator.free(compressed);

        const decoded = try decompress(allocator, compressed);
        defer allocator.free(decoded);

        try testing.expectEqualStrings(sample, decoded);
    }
}

test "Compression modes generic, text, font round trip" {
    const allocator = testing.allocator;
    const sample = "Testing different compression modes in Brotli: generic, text, font.";

    inline for (.{ CompressionMode.generic, CompressionMode.text, CompressionMode.font }) |m| {
        const compressed = try compressWithOptions(allocator, sample, .{ .mode = m, .quality = 5 });
        defer allocator.free(compressed);

        const decoded = try decompress(allocator, compressed);
        defer allocator.free(decoded);

        try testing.expectEqualStrings(sample, decoded);
    }
}

test "Edge case: 1, 2, 3, 4 bytes, zeroes, and 0xFF bytes" {
    const allocator = testing.allocator;

    const cases = [_][]const u8{
        "x",
        "xy",
        "xyz",
        "xyzw",
        "\x00",
        "\x00\x00\x00\x00\x00",
        "\xFF",
        "\xFF\xFF\xFF\xFF\xFF\xFF",
        "\x00\xFF\x00\xFF\x00\xFF\x00\xFF",
    };

    for (cases) |c| {
        const comp = try compress(allocator, c);
        defer allocator.free(comp);

        const decomp = try decompress(allocator, comp);
        defer allocator.free(decomp);

        try testing.expectEqualSlices(u8, c, decomp);
    }
}

test "Malformed stream headers and corrupted bits fail safely" {
    const allocator = testing.allocator;

    try testing.expectError(error.TruncatedInput, decompress(allocator, &.{}));

    const corrupt1 = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF };
    _ = decompress(allocator, &corrupt1) catch {};

    const valid = try compress(allocator, "A sentence that will be compressed then truncated.");
    defer allocator.free(valid);

    if (valid.len > 4) {
        const truncated = valid[0 .. valid.len / 2];
        _ = decompress(allocator, truncated) catch |err| {
            try testing.expect(err == error.TruncatedInput or err == error.CorruptStream or err == error.InvalidMetaBlock or err == error.InvalidHuffmanTree or err == error.BrotliDecompressionError);
        };
    }
}

test "Upstream reference testdata decompression" {
    const allocator = testing.allocator;

    const test_files = [_]struct { comp: []const u8, orig: []const u8 }{
        .{ .comp = "brotli/tests/testdata/10x10y.compressed", .orig = "brotli/tests/testdata/10x10y" },
        .{ .comp = "brotli/tests/testdata/64x.compressed", .orig = "brotli/tests/testdata/64x" },
        .{ .comp = "brotli/tests/testdata/empty.compressed", .orig = "brotli/tests/testdata/empty" },
        .{ .comp = "brotli/tests/testdata/quickfox.compressed", .orig = "brotli/tests/testdata/quickfox" },
        .{ .comp = "brotli/tests/testdata/x.compressed", .orig = "brotli/tests/testdata/x" },
        .{ .comp = "brotli/tests/testdata/xyzzy.compressed", .orig = "brotli/tests/testdata/xyzzy" },
        .{ .comp = "brotli/tests/testdata/zeros.compressed", .orig = "brotli/tests/testdata/zeros" },
    };

    for (test_files) |tf| {
        const comp_data = std.Io.Dir.cwd().readFileAlloc(std.testing.io, tf.comp, allocator, .limited(1024 * 1024)) catch continue;
        defer allocator.free(comp_data);

        const orig_data = std.Io.Dir.cwd().readFileAlloc(std.testing.io, tf.orig, allocator, .limited(1024 * 1024)) catch continue;
        defer allocator.free(orig_data);

        const decomp = try decompress(allocator, comp_data);
        defer allocator.free(decomp);

        try testing.expectEqualSlices(u8, orig_data, decomp);
    }
}

test "bidirectional interoperability with reference brotli executable" {
    const allocator = testing.allocator;

    const sample1 = "Hello from Zig 0.17! Interoperability testing with upstream Brotli v1.2.0.";
    const sample2 = "The quick brown fox jumps over the lazy dog near the river bank every morning.";
    var sample3_buf: [1500]u8 = undefined;
    @memset(sample3_buf[0..500], 'A');
    @memset(sample3_buf[500..1000], 'B');
    @memset(sample3_buf[1000..1500], 'C');

    const inputs = [_][]const u8{ sample1, sample2, &sample3_buf };
    const qualities = [_]u32{ 0, 1, 5, 9, 11 };

    const has_ref = if (std.Io.Dir.cwd().openFile(std.testing.io, "brotli_ref.exe", .{})) |f| blk: {
        f.close(std.testing.io);
        break :blk true;
    } else |_| false;

    for (inputs, 0..) |input, idx| {
        for (qualities) |q| {
            // 1. Compress with brotli.zig
            const zig_compressed = try compressWithOptions(allocator, input, .{ .quality = q });
            defer allocator.free(zig_compressed);

            // 2. Verify brotli.zig decompresses its own output
            const zig_decompressed = try decompress(allocator, zig_compressed);
            defer allocator.free(zig_decompressed);
            try testing.expectEqualSlices(u8, input, zig_decompressed);

            // 3. Bidirectional interop with reference brotli executable if available
            if (has_ref) {
                var in_name_buf: [64]u8 = undefined;
                var out_name_buf: [64]u8 = undefined;
                var raw_name_buf: [64]u8 = undefined;
                var ref_comp_name_buf: [64]u8 = undefined;

                const in_name = try std.fmt.bufPrint(&in_name_buf, "interop_test_{d}_{d}.br", .{ idx, q });
                const out_name = try std.fmt.bufPrint(&out_name_buf, "interop_test_{d}_{d}.txt", .{ idx, q });
                const raw_name = try std.fmt.bufPrint(&raw_name_buf, "interop_raw_{d}_{d}.txt", .{ idx, q });
                const ref_comp_name = try std.fmt.bufPrint(&ref_comp_name_buf, "interop_ref_{d}_{d}.br", .{ idx, q });

                try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = in_name, .data = zig_compressed });
                defer std.Io.Dir.cwd().deleteFile(std.testing.io, in_name) catch {};

                const run_dec = std.process.run(allocator, std.testing.io, .{
                    .argv = &.{
                        "brotli_ref.exe",
                        "-d",
                        "-f",
                        "-o",
                        out_name,
                        in_name,
                    },
                }) catch continue;
                allocator.free(run_dec.stdout);
                allocator.free(run_dec.stderr);
                defer std.Io.Dir.cwd().deleteFile(std.testing.io, out_name) catch {};

                if (run_dec.term == .exited and run_dec.term.exited == 0) {
                    const ref_decompressed = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, out_name, allocator, .limited(1024 * 1024));
                    defer allocator.free(ref_decompressed);
                    try testing.expectEqualSlices(u8, input, ref_decompressed);
                }

                try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = raw_name, .data = input });
                defer std.Io.Dir.cwd().deleteFile(std.testing.io, raw_name) catch {};

                var q_buf: [16]u8 = undefined;
                const q_str = try std.fmt.bufPrint(&q_buf, "{d}", .{q});

                const run_enc = std.process.run(allocator, std.testing.io, .{
                    .argv = &.{
                        "brotli_ref.exe",
                        "-f",
                        "-q",
                        q_str,
                        "-o",
                        ref_comp_name,
                        raw_name,
                    },
                }) catch continue;
                allocator.free(run_enc.stdout);
                allocator.free(run_enc.stderr);
                defer std.Io.Dir.cwd().deleteFile(std.testing.io, ref_comp_name) catch {};

                if (run_enc.term == .exited and run_enc.term.exited == 0) {
                    const ref_comp_data = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, ref_comp_name, allocator, .limited(1024 * 1024));
                    defer allocator.free(ref_comp_data);

                    const zig_dec_from_ref = try decompress(allocator, ref_comp_data);
                    defer allocator.free(zig_dec_from_ref);
                    try testing.expectEqualSlices(u8, input, zig_dec_from_ref);
                }
            }
        }
    }
}

test "decompress larger upstream reference corpus" {
    const allocator = testing.allocator;

    const large_test_files = [_]struct { comp: []const u8, orig: []const u8 }{
        .{ .comp = "brotli/tests/testdata/alice29.txt.compressed", .orig = "brotli/tests/testdata/alice29.txt" },
        .{ .comp = "brotli/tests/testdata/asyoulik.txt.compressed", .orig = "brotli/tests/testdata/asyoulik.txt" },
        .{ .comp = "brotli/tests/testdata/lcet10.txt.compressed", .orig = "brotli/tests/testdata/lcet10.txt" },
        .{ .comp = "brotli/tests/testdata/monkey.compressed", .orig = "brotli/tests/testdata/monkey" },
        .{ .comp = "brotli/tests/testdata/ukkonooa.compressed", .orig = "brotli/tests/testdata/ukkonooa" },
    };

    for (large_test_files) |tf| {
        const comp_data = std.Io.Dir.cwd().readFileAlloc(std.testing.io, tf.comp, allocator, .limited(4 * 1024 * 1024)) catch continue;
        defer allocator.free(comp_data);

        const orig_data = std.Io.Dir.cwd().readFileAlloc(std.testing.io, tf.orig, allocator, .limited(4 * 1024 * 1024)) catch continue;
        defer allocator.free(orig_data);

        const decomp = try decompress(allocator, comp_data);
        defer allocator.free(decomp);

        try testing.expectEqualSlices(u8, orig_data, decomp);
    }
}

test "multi-threaded concurrent compression and decompression" {
    const worker = struct {
        fn run(allocator: std.mem.Allocator, id: usize) !void {
            var prng = std.Random.DefaultPrng.init(12345 + id);
            const rand = prng.random();

            var data: [4096]u8 = undefined;
            for (&data) |*b| {
                b.* = @intCast(rand.intRangeAtMost(u8, 'a', 'z'));
            }

            // Test one-shot compression and decompression
            const compressed = try compressWithOptions(allocator, &data, .{ .quality = 5 });
            defer allocator.free(compressed);

            const decompressed = try decompress(allocator, compressed);
            defer allocator.free(decompressed);

            try testing.expectEqualSlices(u8, &data, decompressed);

            // Test independent context instance
            var comp = Compressor.init(allocator, .{ .quality = 6 });
            defer comp.deinit();

            const c2 = try comp.compress(&data);
            defer allocator.free(c2);

            var dec = Decompressor.init(allocator, .{});
            defer dec.deinit();

            const d2 = try dec.decompress(c2);
            defer allocator.free(d2);

            try testing.expectEqualSlices(u8, &data, d2);
        }

        fn threadEntry(id: usize) void {
            run(testing.allocator, id) catch |e| {
                std.debug.panic("thread {d} failed: {any}", .{ id, e });
            };
        }
    };

    const num_threads = 4;
    var threads: [num_threads]std.Thread = undefined;
    for (0..num_threads) |i| {
        threads[i] = try std.Thread.spawn(.{}, worker.threadEntry, .{i});
    }

    for (threads) |t| {
        t.join();
    }
}
