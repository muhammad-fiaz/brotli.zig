//! Streaming Brotli decompressor.
//!
//! Provides incremental decompression supporting both chunked memory feeds
//! and direct streaming with standard Zig `std.Io.Reader` and `std.Io.Writer`.

const std = @import("std");
const decoder = @import("../decompress/decode.zig");

pub const Options = decoder.Options;
pub const DecompressionOptions = decoder.Options;
pub const Decoder = decoder.Decoder;
pub const DecodeResult = decoder.Result;
pub const ErrorCode = decoder.ErrorCode;

/// Incremental streaming decompression context over the native Brotli decoder.
///
/// Supports arbitrary byte-boundary feeding without requiring the full compressed
/// stream to be present in memory.
pub const StreamingDecompressor = struct {
    inner: Decoder,
    allocator: std.mem.Allocator,
    inbuf: std.ArrayList(u8),
    fed_pos: usize = 0,
    finished_: bool = false,

    /// Initializes a streaming decompressor with the provided allocator and options.
    pub fn init(allocator: std.mem.Allocator, options: DecompressionOptions) StreamingDecompressor {
        return .{
            .inner = Decoder.init(allocator, options),
            .allocator = allocator,
            .inbuf = .empty,
        };
    }

    /// Releases all resources owned by the decompressor.
    pub fn deinit(self: *StreamingDecompressor) void {
        self.inbuf.deinit(self.allocator);
        self.inner.deinit();
    }

    /// Resets the streaming decompressor for reuse with new options without reallocating ringbuffers.
    pub fn reset(self: *StreamingDecompressor, options: DecompressionOptions) void {
        self.inbuf.clearRetainingCapacity();
        self.fed_pos = 0;
        self.finished_ = false;
        self.inner.reset(options);
    }

    /// Feeds input bytes into the internal accumulation buffer.
    pub fn feed(self: *StreamingDecompressor, chunk: []const u8) void {
        self.inbuf.appendSlice(self.allocator, chunk) catch {};
    }

    /// Signals no more input will arrive; flushes any remaining partial data.
    pub fn endInput(self: *StreamingDecompressor) void {
        var empty: []const u8 = &.{};
        var avail: []u8 = &.{};
        _ = self.inner.decompressStream(&empty, &avail, null);
    }

    /// Decodes into `out`; returns bytes written during this call.
    /// Callers should continue invoking until both `isFinished()` and zero output returned.
    pub fn take(self: *StreamingDecompressor, out: []u8) !usize {
        var avail: []u8 = out;
        const total_before = self.inner.partial_pos_out;

        // Feed unconsumed buffered input.
        var unconsumed: []const u8 = self.inbuf.items[self.fed_pos..];
        if (unconsumed.len > 0) {
            const r = self.inner.decompressStream(&unconsumed, &avail, &self.inner.partial_pos_out);
            self.fed_pos = self.inbuf.items.len - unconsumed.len;
            switch (r) {
                .success => self.finished_ = true,
                .needs_more_input, .needs_more_output => {},
                .err => return error.BrotliStreamError,
            }
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

    /// Reads from a `std.Io.Reader` and writes decompressed bytes to a `std.Io.Writer`.
    pub fn read(self: *StreamingDecompressor, reader: *std.Io.Reader, writer: *std.Io.Writer) !void {
        var in_chunk: [16384]u8 = undefined;
        var out_chunk: [16384]u8 = undefined;

        while (!self.isFinished()) {
            const n_in = reader.readSliceShort(&in_chunk) catch |err| return err;
            if (n_in > 0) {
                self.feed(in_chunk[0..n_in]);
            } else {
                self.endInput();
            }

            while (true) {
                const n_out = try self.take(&out_chunk);
                if (n_out > 0) {
                    try writer.writeAll(out_chunk[0..n_out]);
                }
                if (n_out == 0) break;
            }

            if (n_in == 0 and !self.isFinished()) {
                if (self.hasError()) return self.errorCode().toError();
                break;
            }
        }
    }

    /// Returns true if decompression has completed successfully.
    pub fn isFinished(self: *const StreamingDecompressor) bool {
        return self.finished_;
    }

    /// Returns true if a decoding error was recorded.
    pub fn hasError(self: *const StreamingDecompressor) bool {
        return self.inner.errorCode().isError();
    }

    /// Returns the diagnostic error code from the underlying decoder.
    pub fn errorCode(self: *const StreamingDecompressor) ErrorCode {
        return self.inner.errorCode();
    }

    /// Returns the cumulative number of bytes written so far.
    pub fn totalOut(self: *const StreamingDecompressor) u64 {
        return self.inner.partial_pos_out;
    }
};

/// Decompresses from `std.Io.Reader` directly to `std.Io.Writer` with streaming buffers.
pub fn decompressStream(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    options: DecompressionOptions,
) !void {
    var dec = Decoder.init(allocator, options);
    defer dec.deinit();

    var in_buf: [16384]u8 = undefined;
    var out_buf: [16384]u8 = undefined;
    var in_slice: []const u8 = &.{};
    var total_out: u64 = 0;

    var eof = false;
    while (true) {
        if (in_slice.len == 0 and !eof) {
            const n_read = reader.readSliceShort(&in_buf) catch |err| return err;
            if (n_read == 0) {
                eof = true;
                in_slice = &.{};
            } else {
                in_slice = in_buf[0..n_read];
            }
        }

        var avail_out: []u8 = &out_buf;
        const result = dec.decompressStream(&in_slice, &avail_out, &total_out);
        const produced = out_buf.len - avail_out.len;
        if (produced > 0) {
            try writer.writeAll(out_buf[0..produced]);
        }

        switch (result) {
            .success => return,
            .needs_more_output => continue,
            .needs_more_input => {
                if (eof) {
                    if (dec.errorCode().isError()) return dec.errorCode().toError();
                    return error.TruncatedInput;
                }
                continue;
            },
            .err => return dec.errorCode().toError(),
        }
    }
}

// -------------------------------------------------------------------------
// Unit Tests
// -------------------------------------------------------------------------
const testing = std.testing;

test "StreamingDecompressor on empty finalized stream" {
    var sd = StreamingDecompressor.init(testing.allocator, .{});
    defer sd.deinit();
    sd.feed(&.{0x06}); // Empty RFC 7932 stream
    var out: [16]u8 = undefined;
    const n = try sd.take(&out);
    try testing.expectEqual(@as(usize, 0), n);
    try testing.expect(sd.isFinished());
}

test "StreamingDecompressor reset and reuse" {
    var sd = StreamingDecompressor.init(testing.allocator, .{});
    defer sd.deinit();

    sd.feed(&.{0x06});
    var out: [16]u8 = undefined;
    _ = try sd.take(&out);
    try testing.expect(sd.isFinished());

    sd.reset(.{});
    try testing.expect(!sd.isFinished());
    sd.feed(&.{0x06});
    _ = try sd.take(&out);
    try testing.expect(sd.isFinished());
}
