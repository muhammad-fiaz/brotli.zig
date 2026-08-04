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
        input_offset += result.bytes_consumed;

        if (result.is_finished) break;
        if (!result.has_more_output and result.bytes_consumed == 0 and result.bytes_produced == 0) break;
    }

    std.debug.print("Streaming decode: {d} compressed bytes processed\n", .{input_offset});
    std.debug.print("Decoder finished: {}\n", .{dec.isFinished()});
}
