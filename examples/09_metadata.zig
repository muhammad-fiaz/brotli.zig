const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const data = "Data to compress with metadata block attached.";

    var enc = try brotli.encoder.Encoder.init(allocator, .{ .quality = 6 });
    defer enc.deinit();

    var output: [4096]u8 = undefined;

    const metadata = "This is custom metadata attached to the Brotli stream";

    const emit_result = try enc.compressStream(.emit_metadata, metadata, &output);
    _ = emit_result;

    const compress_result = try enc.compressStream(.finish, data, &output);
    const compressed = output[0..compress_result.bytes_produced];

    const decompressed = try brotli.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.print("Metadata block example:\n", .{});
    std.debug.print("  Original data: {d} bytes\n", .{data.len});
    std.debug.print("  Metadata: {d} bytes\n", .{metadata.len});
    std.debug.print("  Compressed: {d} bytes\n", .{compressed.len});
    std.debug.print("  Round-trip OK: {}\n", .{std.mem.eql(u8, data, decompressed)});
}
