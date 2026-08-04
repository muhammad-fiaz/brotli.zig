const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const dictionary_data = "shared dictionary context for better compression";
    const data = "This data benefits from shared dictionary context for better compression ratios.";

    var prepared = try brotli.PreparedDictionary.init(allocator, .raw, dictionary_data, 11);
    defer prepared.deinit();

    var enc = try brotli.encoder.Encoder.init(allocator, .{ .quality = 6 });
    defer enc.deinit();

    try enc.attachPreparedDictionary(&prepared);

    var output: [4096]u8 = undefined;
    const result = try enc.compressStream(.finish, data, &output);
    const compressed = output[0..result.bytes_produced];

    var dec = try brotli.decoder.Decoder.init(allocator, .{});
    defer dec.deinit();

    try dec.attachDictionary(.raw, dictionary_data);

    var dec_output: [4096]u8 = undefined;
    const dec_result = try dec.decompressStream(compressed, &dec_output);
    switch (dec_result) {
        .success => {},
        else => return error.DecompressionFailed,
    }

    std.debug.print("Shared dictionary example:\n", .{});
    std.debug.print("  Dictionary size: {d} bytes\n", .{dictionary_data.len});
    std.debug.print("  Data size: {d} bytes\n", .{data.len});
    std.debug.print("  Compressed: {d} bytes\n", .{compressed.len});
    std.debug.print("  Prepared dictionary attached and used successfully\n", .{});
    std.debug.print("  Round-trip OK: {}\n", .{std.mem.eql(u8, data, dec_output[0..data.len])});
}
