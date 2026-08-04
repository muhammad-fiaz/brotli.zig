const std = @import("std");
const c = @import("../c.zig").c;
const types = @import("../common/types.zig");
const options_mod = @import("options.zig");

pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return decompressWith(allocator, input, .{});
}

pub fn decompressWith(allocator: std.mem.Allocator, input: []const u8, options: options_mod.DecoderOptions) ![]u8 {
    const handle = c.BrotliDecoderCreateInstance(null, null, null) orelse return error.OutOfMemory;
    defer c.BrotliDecoderDestroyInstance(handle);
    _ = options.apply(handle) catch {};

    var buf_size: usize = input.len *| 4;
    if (buf_size < 256) buf_size = 256;

    var buf = try allocator.alloc(u8, buf_size);
    var input_pos: usize = 0;
    var output_pos: usize = 0;

    while (true) {
        var available_in: usize = input.len -| input_pos;
        var next_in: [*c]const u8 = input.ptr + input_pos;
        var available_out: usize = buf.len - output_pos;
        var next_out: [*c]u8 = buf.ptr + output_pos;

        const result = c.BrotliDecoderDecompressStream(
            handle,
            &available_in,
            &next_in,
            &available_out,
            &next_out,
            null,
        );

        input_pos += available_in;
        output_pos = buf.len - available_out;

        switch (result) {
            c.BROTLI_DECODER_RESULT_SUCCESS => {
                if (output_pos < buf.len) {
                    return allocator.realloc(buf, output_pos) catch buf[0..output_pos];
                }
                return buf;
            },
            c.BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT => {
                const new_buf_size = buf.len *| 2;
                const new_buf = try allocator.alloc(u8, new_buf_size);
                @memcpy(new_buf[0..output_pos], buf[0..output_pos]);
                allocator.free(buf);
                buf = new_buf;
                continue;
            },
            else => {
                allocator.free(buf);
                return error.DecompressionFailed;
            },
        }
    }
}

test "oneshot decompress basic" {
    const original = "Hello, Brotli oneshot decompression!";
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, original, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(original, decompressed);
}

test "oneshot decompress empty input roundtrip" {
    const original = "";
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, original, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(original, decompressed);
}

test "oneshot decompress corrupt data" {
    const corrupt = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF };
    const result = decompress(std.testing.allocator, &corrupt);
    try std.testing.expectError(error.DecompressionFailed, result);
}

test "oneshot decompress roundtrip 100 bytes" {
    const data = "A" ** 100;
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(data, decompressed);
}

test "oneshot decompress roundtrip 500 bytes" {
    const data = "Hello, Brotli! " ++ ("abcde" ** 97);
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(data, decompressed);
}

test "oneshot decompress roundtrip 1000 bytes" {
    const data = ("repeating pattern for compression test " ** 28)[0..1000];
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(data, decompressed);
}

test "oneshot decompress roundtrip 4096 bytes" {
    var data: [4096]u8 = undefined;
    for (&data, 0..) |*b, i| b.* = @intCast(i % 251);
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, &data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(&data, decompressed);
}

test "oneshot decompress roundtrip 10000 bytes" {
    var data: [10000]u8 = undefined;
    for (&data, 0..) |*b, i| b.* = @intCast(i % 256);
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, &data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(&data, decompressed);
}

test "oneshot decompress roundtrip 65536 bytes" {
    var data: [65536]u8 = undefined;
    for (&data, 0..) |*b, i| b.* = @intCast(i % 128);
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, &data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(&data, decompressed);
}

test "oneshot decompress roundtrip all zeros 1000" {
    const data = ([1]u8{0} ** 1000);
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, &data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(&data, decompressed);
}

test "oneshot decompress roundtrip random data 2000 bytes" {
    var data: [2000]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(42);
    prng.random().bytes(&data);
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, &data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(&data, decompressed);
}

test "oneshot decompress with custom quality" {
    const data = "Quality test data " ++ ("xyz" ** 200);
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, data, .{ .quality = 6 });
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(data, decompressed);
}

test "oneshot decompressWithOptions basic" {
    const original = "WithOptions decompression test";
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, original, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompressWith(std.testing.allocator, compressed, .{});
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(original, decompressed);
}

test "oneshot decompressWithOptions with disable_ring_buffer_reallocation" {
    const original = "Ring buffer options test";
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, original, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompressWith(std.testing.allocator, compressed, .{
        .disable_ring_buffer_reallocation = true,
    });
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(original, decompressed);
}

test "oneshot decompress large window roundtrip" {
    const original = "Large window oneshot roundtrip test";
    const compressed = try @import("../encoder/oneshot.zig").compress(std.testing.allocator, original, .{
        .large_window = true,
        .lgwin = 26,
    });
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompressWith(std.testing.allocator, compressed, .{
        .large_window = true,
    });
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(original, decompressed);
}
