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
