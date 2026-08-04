const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const data = "SGVsbG8gV29ybGQhIFRoaXMgaXMgYmFzZTY0IGVuY29kZWQgZGF0YS4=";

    const options = brotli.EncoderOptions{
        .quality = 6,
        .base64_mode = 1,
        .max_base64_regions = 4,
    };

    const compressed = try brotli.compressWithOptions(allocator, data, options);
    defer allocator.free(compressed);

    const decompressed = try brotli.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.print("Base64 mode example:\n", .{});
    std.debug.print("  Input size: {d} bytes\n", .{data.len});
    std.debug.print("  Compressed: {d} bytes\n", .{compressed.len});
    std.debug.print("  Round-trip OK: {}\n", .{std.mem.eql(u8, data, decompressed)});
}
