const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    const data = "Hello, Brotli from Zig!";

    const compressed = try brotli.compress(allocator, data);
    defer allocator.free(compressed);

    const decompressed = try brotli.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.print("Compressed {d} -> {d} bytes\n", .{ data.len, compressed.len });
    std.debug.print("Decompressed back to {d} bytes\n", .{decompressed.len});
    std.debug.print("Round-trip OK: {}\n", .{std.mem.eql(u8, data, decompressed)});
}
