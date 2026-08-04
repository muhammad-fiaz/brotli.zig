const std = @import("std");
const c = @import("../c.zig").c;
const types = @import("../common/types.zig");

pub const EncoderOptions = struct {
    mode: ?types.EncoderMode = null,
    quality: ?u4 = null,
    lgwin: ?u5 = null,
    lgblock: ?u5 = null,
    disable_literal_context_modeling: ?bool = null,
    size_hint: ?usize = null,
    large_window: ?bool = null,
    npostfix: ?u2 = null,
    ndirect: ?u7 = null,
    stream_offset: ?usize = null,
    base64_mode: ?u1 = null,
    max_base64_regions: ?u4 = null,

    pub fn default() EncoderOptions {
        return .{};
    }

    pub fn apply(self: EncoderOptions, state: ?*c.BrotliEncoderState) !void {
        if (self.mode) |mode| {
            if (c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_MODE, @intCast(@intFromEnum(mode))) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
        if (self.quality) |quality| {
            if (quality > 11) return error.InvalidParameter;
            if (c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_QUALITY, quality) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
        if (self.lgwin) |lgwin| {
            if (c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_LGWIN, lgwin) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
        if (self.lgblock) |lgblock| {
            if (c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_LGBLOCK, lgblock) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
        if (self.disable_literal_context_modeling) |v| {
            if (c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_DISABLE_LITERAL_CONTEXT_MODELING, @intFromBool(v)) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
        if (self.size_hint) |v| {
            if (c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_SIZE_HINT, @intCast(v)) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
        if (self.large_window) |v| {
            if (c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_LARGE_WINDOW, @intFromBool(v)) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
        if (self.npostfix) |v| {
            if (c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_NPOSTFIX, v) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
        if (self.ndirect) |v| {
            if (c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_NDIRECT, v) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
        if (self.stream_offset) |v| {
            if (c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_STREAM_OFFSET, @intCast(v)) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
        if (self.base64_mode) |v| {
            if (c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_BASE64_MODE, v) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
        if (self.max_base64_regions) |v| {
            if (c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_MAX_BASE64_REGIONS, v) == c.BROTLI_FALSE)
                return error.InvalidParameter;
        }
    }
};
