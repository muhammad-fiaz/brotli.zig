const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const data = "Testing large window Brotli mode with lgwin greater than 24.";

    const options = brotli.EncoderOptions{
        .quality = 6,
        .lgwin = 26,
        .large_window = true,
    };

    const compressed = try brotli.compressWithOptions(allocator, data, options);
    defer allocator.free(compressed);

    var dec_options = brotli.decoder.DecoderOptions{};
    dec_options.large_window = true;

    const decompressed = try brotli.decompressWithOptions(allocator, compressed, dec_options);
    defer allocator.free(decompressed);

    std.debug.print("Large window mode (lgwin=26):\n", .{});
    std.debug.print("  Compressed {d} -> {d} bytes\n", .{ data.len, compressed.len });
    std.debug.print("  Round-trip OK: {}\n", .{std.mem.eql(u8, data, decompressed)});
}
