const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const original = "This text will be compressed and then decompressed in streaming mode.";
    const compressed = try brotli.compress(allocator, original);
    defer allocator.free(compressed);

    var dec = try brotli.decoder.Decoder.init(allocator, .{});
    defer dec.deinit();

    var output: [4096]u8 = undefined;
    var input_offset: usize = 0;

    const chunk_size = 8;
    while (input_offset < compressed.len) {
        const end = @min(input_offset + chunk_size, compressed.len);
        const chunk = compressed[input_offset..end];

        const result = try dec.decompressStream(chunk, &output);
        input_offset = end;

        switch (result) {
            .success => break,
            .needs_more_input => continue,
            .needs_more_output => continue,
            .@"error" => |e| {
                std.debug.print("Decompression error: {s}\n", .{e.message});
                return error.DecompressionFailed;
            },
        }
    }

    std.debug.print("Streaming decode: {d} compressed bytes processed\n", .{compressed.len});
    std.debug.print("Decoder finished: {}\n", .{dec.isFinished()});
}
