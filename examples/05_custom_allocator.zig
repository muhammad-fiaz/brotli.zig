const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const data = "Using a custom arena allocator with brotli.zig";

    const compressed = try brotli.compress(allocator, data);
    const decompressed = try brotli.decompress(allocator, compressed);

    std.debug.print("Arena allocator test:\n", .{});
    std.debug.print("  Original: {d} bytes\n", .{data.len});
    std.debug.print("  Compressed: {d} bytes\n", .{compressed.len});
    std.debug.print("  Decompressed: {d} bytes\n", .{decompressed.len});
    std.debug.print("  Round-trip OK: {}\n", .{std.mem.eql(u8, data, decompressed)});
}
