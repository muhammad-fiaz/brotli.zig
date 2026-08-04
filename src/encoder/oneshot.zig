const std = @import("std");
const c = @import("../c.zig").c;
const types = @import("../common/types.zig");
const options_mod = @import("options.zig");

pub fn compress(allocator: std.mem.Allocator, input: []const u8, options: options_mod.EncoderOptions) ![]u8 {
    const quality: c_int = if (options.quality) |q| @intCast(q) else c.BROTLI_DEFAULT_QUALITY;
    const lgwin: c_int = if (options.lgwin) |w| @intCast(w) else c.BROTLI_DEFAULT_WINDOW;
    const mode: types.EncoderMode = options.mode orelse .generic;

    const max_size = c.BrotliEncoderMaxCompressedSize(input.len);
    if (max_size == 0) return error.OutOfMemory;

    const buf = try allocator.alloc(u8, max_size);
    errdefer allocator.free(buf);

    var encoded_size: usize = max_size;
    const result = c.BrotliEncoderCompress(
        quality,
        lgwin,
        @intCast(@intFromEnum(mode)),
        input.len,
        input.ptr,
        &encoded_size,
        buf.ptr,
    );

    if (result == c.BROTLI_FALSE) {
        allocator.free(buf);
        return error.InvalidParameter;
    }

    return if (encoded_size < max_size)
        allocator.realloc(buf, encoded_size) catch buf[0..encoded_size]
    else
        buf;
}
