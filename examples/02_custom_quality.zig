const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    const data = "This is sample text for Brotli compression with custom quality settings.";

    const options = brotli.EncoderOptions{
        .quality = 5,
        .lgwin = 18,
        .mode = .text,
    };

    const compressed = try brotli.compressWithOptions(allocator, data, options);
    defer allocator.free(compressed);

    const decompressed = try brotli.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.print("Quality 5, lgwin 18, mode=text:\n", .{});
    std.debug.print("  Compressed {d} -> {d} bytes\n", .{ data.len, compressed.len });
    std.debug.print("  Round-trip OK: {}\n", .{std.mem.eql(u8, data, decompressed)});
}
