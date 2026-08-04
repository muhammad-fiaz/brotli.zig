const std = @import("std");
const c = @import("../c.zig").c;
const types = @import("../common/types.zig");
const allocator_mod = @import("../common/allocator.zig");
const options_mod = @import("options.zig");

pub const Decoder = struct {
    handle: ?*c.BrotliDecoderState,
    c_allocator: allocator_mod.CAllocator,

    pub fn init(allocator: std.mem.Allocator, options: options_mod.DecoderOptions) !Decoder {
        const ca = allocator_mod.CAllocator.fromAllocator(allocator);
        const handle = c.BrotliDecoderCreateInstance(
            @ptrCast(ca.alloc_fn),
            @ptrCast(ca.free_fn),
            ca.opaque_ptr,
        );
        if (handle == null) {
            ca.deinit();
            return error.OutOfMemory;
        }
        try options.apply(handle);
        return .{ .handle = handle, .c_allocator = ca };
    }

    pub fn deinit(self: *Decoder) void {
        if (self.handle) |handle| {
            c.BrotliDecoderDestroyInstance(handle);
            self.handle = null;
        }
        self.c_allocator.deinit();
    }

    pub fn setParameter(self: Decoder, param: types.DecoderParameter, value: u32) !void {
        if (self.handle == null) return error.InvalidParameter;
        if (c.BrotliDecoderSetParameter(self.handle, @intCast(@intFromEnum(param)), value) == c.BROTLI_FALSE)
            return error.InvalidParameter;
    }

    pub fn decompressStream(self: Decoder, input: []const u8, output: []u8) !types.StreamResult {
        if (self.handle == null) return error.DecompressionFailed;

        var available_in: usize = input.len;
        var next_in_ptr: [*c]const u8 = input.ptr;
        var available_out: usize = output.len;
        var next_out_ptr: [*c]u8 = output.ptr;

        const result = c.BrotliDecoderDecompressStream(
            self.handle,
            &available_in,
            &next_in_ptr,
            &available_out,
            &next_out_ptr,
            null,
        );

        const consumed = input.len - available_in;
        const produced = output.len - available_out;

        return switch (result) {
            c.BROTLI_DECODER_RESULT_SUCCESS => .{
                .bytes_consumed = consumed,
                .bytes_produced = produced,
                .has_more_output = false,
                .is_finished = true,
            },
            c.BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT => .{
                .bytes_consumed = consumed,
                .bytes_produced = produced,
                .has_more_output = c.BrotliDecoderHasMoreOutput(self.handle) != 0,
                .is_finished = false,
            },
            c.BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT => .{
                .bytes_consumed = consumed,
                .bytes_produced = produced,
                .has_more_output = true,
                .is_finished = false,
            },
            c.BROTLI_DECODER_RESULT_ERROR => return error.DecompressionFailed,
            else => return error.DecompressionFailed,
        };
    }

    pub fn decompressBuffer(self: Decoder, input: []const u8, output: []u8) !types.StreamResult {
        var available_in: usize = input.len;
        var next_in: [*c]const u8 = input.ptr;
        var available_out: usize = output.len;
        var next_out: [*c]u8 = output.ptr;

        const result = c.BrotliDecoderDecompressStream(
            self.handle,
            &available_in,
            &next_in,
            &available_out,
            &next_out,
            null,
        );

        const consumed = input.len - available_in;
        const produced = output.len - available_out;

        return switch (result) {
            c.BROTLI_DECODER_RESULT_SUCCESS => .{
                .bytes_consumed = consumed,
                .bytes_produced = produced,
                .has_more_output = false,
                .is_finished = true,
            },
            c.BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT => .{
                .bytes_consumed = consumed,
                .bytes_produced = produced,
                .has_more_output = c.BrotliDecoderHasMoreOutput(self.handle) != 0,
                .is_finished = false,
            },
            c.BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT => .{
                .bytes_consumed = consumed,
                .bytes_produced = produced,
                .has_more_output = true,
                .is_finished = false,
            },
            c.BROTLI_DECODER_RESULT_ERROR => return error.DecompressionFailed,
            else => return error.DecompressionFailed,
        };
    }

    pub fn isUsed(self: Decoder) bool {
        if (self.handle == null) return false;
        return c.BrotliDecoderIsUsed(self.handle) != 0;
    }

    pub fn isFinished(self: Decoder) bool {
        if (self.handle == null) return false;
        return c.BrotliDecoderIsFinished(self.handle) != 0;
    }

    pub fn hasMoreOutput(self: Decoder) bool {
        if (self.handle == null) return false;
        return c.BrotliDecoderHasMoreOutput(self.handle) != 0;
    }

    pub fn takeOutput(self: Decoder, size: ?*usize) ?[]const u8 {
        if (self.handle == null) return null;
        const ptr = c.BrotliDecoderTakeOutput(self.handle, size);
        if (ptr == null) return null;
        const len = if (size) |s| s.* else 0;
        return ptr[0..len];
    }

    pub fn attachDictionary(self: Decoder, dict_type: types.DictionaryType, data: []const u8) !void {
        if (self.handle == null) return error.InvalidDictionary;
        if (c.BrotliDecoderAttachDictionary(
            self.handle,
            @intCast(@intFromEnum(dict_type)),
            data.len,
            data.ptr,
        ) == c.BROTLI_FALSE)
            return error.InvalidDictionary;
    }

    pub fn setMetadataCallbacks(
        self: Decoder,
        start_fn: ?*const fn (?*anyopaque, usize) callconv(.c) void,
        chunk_fn: ?*const fn (?*anyopaque, [*c]const u8, usize) callconv(.c) void,
        opaque_ptr: ?*anyopaque,
    ) void {
        if (self.handle) |handle| {
            c.BrotliDecoderSetMetadataCallbacks(handle, start_fn, chunk_fn, opaque_ptr);
        }
    }

    pub fn getErrorCode(self: Decoder) types.ErrorCode {
        if (self.handle == null) return .error_unreachable;
        return types.ErrorCode.fromNative(c.BrotliDecoderGetErrorCode(self.handle));
    }

    pub fn errorString(self: Decoder) []const u8 {
        if (self.handle == null) return "no decoder instance";
        const code = c.BrotliDecoderGetErrorCode(self.handle);
        const ptr = c.BrotliDecoderErrorString(code);
        return std.mem.sliceTo(ptr, 0);
    }
};

test "decoder init and deinit" {
    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();
    try std.testing.expect(dec.handle != null);
}

test "decoder setParameter disable_ring_buffer_reallocation" {
    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();
    try dec.setParameter(.disable_ring_buffer_reallocation, 1);
}

test "decoder setParameter large_window" {
    var dec = try Decoder.init(std.testing.allocator, .{ .large_window = true });
    defer dec.deinit();
    try dec.setParameter(.large_window, 1);
}

test "decoder decompressStream success" {
    const original = "Hello, decoder streaming!";
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, original, .{});
    defer std.testing.allocator.free(compressed);

    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();

    var output: [256]u8 = undefined;
    const result = try dec.decompressStream(compressed, &output);
    try std.testing.expect(result.is_finished);
    try std.testing.expect(result.bytes_consumed == compressed.len);
    try std.testing.expect(result.bytes_produced == original.len);
}

test "decoder isUsed" {
    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();
    try std.testing.expect(!dec.isUsed());
}

test "decoder isFinished before and after decompression" {
    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();

    const original = "Finished state test";
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, original, .{});
    defer std.testing.allocator.free(compressed);

    var output: [256]u8 = undefined;
    _ = try dec.decompressStream(compressed, &output);
    try std.testing.expect(dec.isFinished());
}

test "decoder hasMoreOutput" {
    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();
    try std.testing.expect(!dec.hasMoreOutput());
}

test "decoder takeOutput" {
    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();

    var size: usize = 0;
    const taken = dec.takeOutput(&size);
    try std.testing.expect(taken == null);
}

test "decoder getErrorCode after successful decode" {
    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();

    const original = "Error code test";
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, original, .{});
    defer std.testing.allocator.free(compressed);

    var output: [256]u8 = undefined;
    _ = try dec.decompressStream(compressed, &output);
    const code = dec.getErrorCode();
    try std.testing.expectEqual(types.ErrorCode.success, code);
}

test "decoder errorString" {
    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();
    const str = dec.errorString();
    try std.testing.expect(str.len > 0);
}

test "decoder decompressStream with corrupt data" {
    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();

    const corrupt = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF };
    var output: [256]u8 = undefined;
    const result = dec.decompressStream(&corrupt, &output);
    try std.testing.expectError(error.DecompressionFailed, result);
}

test "decoder decompressStream needs_more_input" {
    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();

    const partial = [_]u8{ 0x0B, 0x00, 0x00 };
    var output: [256]u8 = undefined;
    const result = try dec.decompressStream(&partial, &output);
    try std.testing.expect(!result.is_finished);
}

test "decoder decompressStream needs_more_output" {
    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();

    const original = "This is a larger test string to trigger needs_more_output in the streaming decoder";
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, original, .{});
    defer std.testing.allocator.free(compressed);

    var output: [8]u8 = undefined;
    const result = try dec.decompressStream(compressed, &output);
    try std.testing.expect(!result.is_finished);
    try std.testing.expect(result.has_more_output);
}

test "decoder roundtrip streaming large data" {
    var data: [1000]u8 = undefined;
    for (&data, 0..) |*b, i| b.* = @intCast(i % 251);
    const original: []const u8 = &data;

    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, original, .{});
    defer std.testing.allocator.free(compressed);

    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();

    var dec_output: [2000]u8 = undefined;
    const result = try dec.decompressStream(compressed, &dec_output);
    try std.testing.expect(result.is_finished);
    try std.testing.expectEqual(original.len, result.bytes_produced);
}

test "decoder with all options" {
    var dec = try Decoder.init(std.testing.allocator, .{
        .disable_ring_buffer_reallocation = true,
        .large_window = false,
    });
    defer dec.deinit();

    const original = "Decoder options test";
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, original, .{});
    defer std.testing.allocator.free(compressed);

    var output: [256]u8 = undefined;
    const result = try dec.decompressStream(compressed, &output);
    try std.testing.expect(result.is_finished);
}

const MetadataContext = struct {
    var received_size: usize = 0;
    var received_data: [4096]u8 = undefined;
    var data_offset: usize = 0;

    pub fn reset() void {
        received_size = 0;
        data_offset = 0;
    }

    pub fn startFn(ctx: ?*anyopaque, size: usize) callconv(.c) void {
        _ = ctx;
        received_size = size;
        data_offset = 0;
    }

    pub fn chunkFn(ctx: ?*anyopaque, data_ptr: [*c]const u8, size: usize) callconv(.c) void {
        _ = ctx;
        if (data_ptr) |ptr| {
            const chunk = ptr[0..size];
            @memcpy(received_data[data_offset..][0..size], chunk);
            data_offset += size;
        }
    }
};

test "decoder setMetadataCallbacks with metadata block" {
    var enc = try @import("../encoder/encoder.zig").Encoder.init(std.testing.allocator, .{ .quality = 6 });
    defer enc.deinit();

    var output: [4096]u8 = undefined;
    var total: usize = 0;

    const meta_result = try enc.compressStream(.emit_metadata, "test metadata", output[total..]);
    total += meta_result.bytes_produced;
    while (enc.hasMoreOutput()) {
        const extra = try enc.compressStream(.process, &.{}, output[total..]);
        total += extra.bytes_produced;
    }
    const finish_result = try enc.compressStream(.finish, "real data", output[total..]);
    total += finish_result.bytes_produced;

    const compressed = output[0..total];

    var dec = try Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();

    MetadataContext.reset();
    dec.setMetadataCallbacks(MetadataContext.startFn, MetadataContext.chunkFn, null);

    var dec_output: [256]u8 = undefined;
    const result = try dec.decompressStream(compressed, &dec_output);
    try std.testing.expect(result.is_finished);
    try std.testing.expectEqual(@as(usize, 13), MetadataContext.received_size);
    try std.testing.expectEqualStrings("test metadata", MetadataContext.received_data[0..MetadataContext.received_size]);
    try std.testing.expectEqualStrings("real data", dec_output[0..result.bytes_produced]);
}
