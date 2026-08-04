const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const data =
        \\First chunk of data to compress in streaming mode.
        \\This demonstrates the streaming encoder API.
        \\Second chunk follows immediately after the first.
        \\Third chunk is the final piece of input data.
    ;

    var enc = try brotli.encoder.Encoder.init(allocator, .{ .quality = 6 });
    defer enc.deinit();

    var output: [4096]u8 = undefined;
    var total_compressed: usize = 0;
    var input_offset: usize = 0;

    const chunk_size = 32;
    while (input_offset < data.len) {
        const end = @min(input_offset + chunk_size, data.len);
        const chunk = data[input_offset..end];

        const op: brotli.EncoderOperation = if (end >= data.len) .finish else .process;
        const result = try enc.compressStream(op, chunk, &output);
        total_compressed += result.bytes_produced;
        input_offset += result.bytes_consumed;

        if (result.has_more_output) {
            _ = try enc.compressStream(.finish, &.{}, &output);
        }
    }

    while (!enc.isFinished()) {
        const result = try enc.compressStream(.finish, &.{}, &output);
        total_compressed += result.bytes_produced;
    }

    std.debug.print("Streaming encode: {d} bytes -> ~{d} bytes compressed\n", .{ data.len, total_compressed });
}
