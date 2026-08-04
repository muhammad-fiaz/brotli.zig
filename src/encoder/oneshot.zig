const std = @import("std");
const c = @import("../c.zig").c;
const types = @import("../common/types.zig");
const options_mod = @import("options.zig");

pub fn compress(allocator: std.mem.Allocator, input: []const u8, options: options_mod.EncoderOptions) ![]u8 {
    const quality: c_int = if (options.quality) |q| @intCast(q) else c.BROTLI_DEFAULT_QUALITY;
    const lgwin: c_int = if (options.lgwin) |w| @intCast(w) else c.BROTLI_DEFAULT_WINDOW;
    const mode: types.EncoderMode = options.mode orelse .generic;

    const max_size = c.BrotliEncoderMaxCompressedSize(input.len);
    if (max_size == 0) return error.OutOfMemory;

    const buf = try allocator.alloc(u8, max_size);
    errdefer allocator.free(buf);

    var encoded_size: usize = max_size;
    const result = c.BrotliEncoderCompress(
        quality,
        lgwin,
        @intCast(@intFromEnum(mode)),
        input.len,
        input.ptr,
        &encoded_size,
        buf.ptr,
    );

    if (result == c.BROTLI_FALSE) {
        allocator.free(buf);
        return error.InvalidParameter;
    }

    return if (encoded_size < max_size)
        allocator.realloc(buf, encoded_size) catch buf[0..encoded_size]
    else
        buf;
}

test "oneshot compress basic" {
    const data = "Hello, Brotli oneshot compression!";
    const compressed = try compress(std.testing.allocator, data, .{});
    defer std.testing.allocator.free(compressed);
    try std.testing.expect(compressed.len > 0);
    try std.testing.expect(compressed.len < data.len);
}

test "oneshot compress empty input" {
    const data = "";
    const compressed = try compress(std.testing.allocator, data, .{});
    defer std.testing.allocator.free(compressed);
    try std.testing.expect(compressed.len >= 0);
}

test "oneshot compress with quality 0" {
    const data = "Quality zero compression test";
    const compressed = try compress(std.testing.allocator, data, .{ .quality = 0 });
    defer std.testing.allocator.free(compressed);
    try std.testing.expect(compressed.len > 0);
}

test "oneshot compress with quality 11" {
    const data = "Quality eleven compression test";
    const compressed = try compress(std.testing.allocator, data, .{ .quality = 11 });
    defer std.testing.allocator.free(compressed);
    try std.testing.expect(compressed.len > 0);
}

test "oneshot compress with mode text" {
    const data = "Text mode compression test with UTF-8 content";
    const compressed = try compress(std.testing.allocator, data, .{ .mode = .text });
    defer std.testing.allocator.free(compressed);
    try std.testing.expect(compressed.len > 0);
}

test "oneshot compress with mode font" {
    const data = "Font mode compression test";
    const compressed = try compress(std.testing.allocator, data, .{ .mode = .font });
    defer std.testing.allocator.free(compressed);
    try std.testing.expect(compressed.len > 0);
}

test "oneshot compress roundtrip" {
    const data = "Roundtrip oneshot test data for compress and decompress";
    const compressed = try compress(std.testing.allocator, data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try @import("../decoder/oneshot.zig").decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(data, decompressed);
}

test "oneshot compress large data 1000 bytes" {
    var data: [1000]u8 = undefined;
    for (&data, 0..) |*b, i| b.* = @intCast(i % 251);
    const compressed = try compress(std.testing.allocator, &data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try @import("../decoder/oneshot.zig").decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(&data, decompressed);
}

test "oneshot compress large data 65536 bytes" {
    var data: [65536]u8 = undefined;
    for (&data, 0..) |*b, i| b.* = @intCast(i % 128);
    const compressed = try compress(std.testing.allocator, &data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try @import("../decoder/oneshot.zig").decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(&data, decompressed);
}

test "oneshot compress all zeros 1000" {
    const data = ([1]u8{0} ** 1000);
    const compressed = try compress(std.testing.allocator, &data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try @import("../decoder/oneshot.zig").decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(&data, decompressed);
}

test "oneshot compress random data 2000 bytes" {
    var data: [2000]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(42);
    prng.random().bytes(&data);
    const compressed = try compress(std.testing.allocator, &data, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try @import("../decoder/oneshot.zig").decompress(std.testing.allocator, compressed);
    defer std.testing.allocator.free(decompressed);
    try std.testing.expectEqualStrings(&data, decompressed);
}

test "oneshot compress with lgwin" {
    const data = "lgwin parameter test";
    const compressed = try compress(std.testing.allocator, data, .{ .lgwin = 18 });
    defer std.testing.allocator.free(compressed);
    try std.testing.expect(compressed.len > 0);
}

test "oneshot compress with all options" {
    const data = "All encoder options oneshot test";
    const compressed = try compress(std.testing.allocator, data, .{
        .mode = .text,
        .quality = 6,
        .lgwin = 18,
        .lgblock = 18,
    });
    defer std.testing.allocator.free(compressed);
    try std.testing.expect(compressed.len > 0);
}
