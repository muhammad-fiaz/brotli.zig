const std = @import("std");
const c = @import("../c.zig").c;
const types = @import("../common/types.zig");

pub const DecoderOptions = struct {
    disable_ring_buffer_reallocation: ?bool = null,
    large_window: ?bool = null,

    pub fn default() DecoderOptions {
        return .{};
    }

    pub fn apply(self: DecoderOptions, state: ?*c.BrotliDecoderState) !void {
        if (self.disable_ring_buffer_reallocation) |v| {
            if (c.BrotliDecoderSetParameter(state, c.BROTLI_DECODER_PARAM_DISABLE_RING_BUFFER_REALLOCATION, @intFromBool(v)) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
        if (self.large_window) |v| {
            if (c.BrotliDecoderSetParameter(state, c.BROTLI_DECODER_PARAM_LARGE_WINDOW, @intFromBool(v)) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
    }
};

test "decoderOptions default" {
    const opts = DecoderOptions.default();
    try std.testing.expect(opts.disable_ring_buffer_reallocation == null);
    try std.testing.expect(opts.large_window == null);
}

test "decoderOptions with disable_ring_buffer_reallocation" {
    const opts = DecoderOptions{ .disable_ring_buffer_reallocation = true };
    try std.testing.expect(opts.disable_ring_buffer_reallocation == true);
}

test "decoderOptions with large_window" {
    const opts = DecoderOptions{ .large_window = true };
    try std.testing.expect(opts.large_window == true);
}

test "decoderOptions with both params" {
    const opts = DecoderOptions{
        .disable_ring_buffer_reallocation = true,
        .large_window = false,
    };
    try std.testing.expect(opts.disable_ring_buffer_reallocation == true);
    try std.testing.expect(opts.large_window == false);
}

test "decoderOptions apply disable_ring_buffer_reallocation" {
    const handle = c.BrotliDecoderCreateInstance(null, null, null);
    defer c.BrotliDecoderDestroyInstance(handle);
    const opts = DecoderOptions{ .disable_ring_buffer_reallocation = true };
    try opts.apply(handle);
}

test "decoderOptions apply large_window" {
    const handle = c.BrotliDecoderCreateInstance(null, null, null);
    defer c.BrotliDecoderDestroyInstance(handle);
    const opts = DecoderOptions{ .large_window = true };
    try opts.apply(handle);
}

test "decoderOptions apply both" {
    const handle = c.BrotliDecoderCreateInstance(null, null, null);
    defer c.BrotliDecoderDestroyInstance(handle);
    const opts = DecoderOptions{
        .disable_ring_buffer_reallocation = false,
        .large_window = true,
    };
    try opts.apply(handle);
}
