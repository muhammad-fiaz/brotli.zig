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
    var total_decompressed: usize = 0;
    var input_offset: usize = 0;

    const chunk_size = 8;
    while (input_offset < compressed.len) {
        const end = @min(input_offset + chunk_size, compressed.len);
        const chunk = compressed[input_offset..end];

        const result = try dec.decompressStream(chunk, &output);
        switch (result) {
            .success => {
                var size: usize = 0;
                if (dec.takeOutput(&size)) |_| {
                    total_decompressed += size;
                }
                input_offset = end;
                break;
            },
            .needs_more_input => {
                input_offset = end;
                continue;
            },
            .needs_more_output => {
                total_decompressed += output.len;
                continue;
            },
            .@"error" => |e| {
                std.debug.print("Decompression error: {s}\n", .{e.message});
                return error.DecompressionFailed;
            },
        }
    }

    std.debug.print("Streaming decode: {d} compressed -> ~{d} decompressed bytes\n", .{ compressed.len, total_decompressed });
}
