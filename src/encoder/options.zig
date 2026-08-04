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

test "encoderOptions default" {
    const opts = EncoderOptions.default();
    try std.testing.expect(opts.mode == null);
    try std.testing.expect(opts.quality == null);
    try std.testing.expect(opts.lgwin == null);
}

test "encoderOptions with mode" {
    const opts = EncoderOptions{ .mode = .text };
    try std.testing.expectEqual(types.EncoderMode.text, opts.mode.?);
}

test "encoderOptions with quality" {
    const opts = EncoderOptions{ .quality = 5 };
    try std.testing.expectEqual(@as(?u4, 5), opts.quality);
}

test "encoderOptions with lgwin" {
    const opts = EncoderOptions{ .lgwin = 18 };
    try std.testing.expectEqual(@as(?u5, 18), opts.lgwin);
}

test "encoderOptions with lgblock" {
    const opts = EncoderOptions{ .lgblock = 20 };
    try std.testing.expectEqual(@as(?u5, 20), opts.lgblock);
}

test "encoderOptions with all params" {
    const opts = EncoderOptions{
        .mode = .font,
        .quality = 9,
        .lgwin = 22,
        .lgblock = 22,
        .disable_literal_context_modeling = true,
        .size_hint = 4096,
        .large_window = false,
        .npostfix = 1,
        .ndirect = 5,
        .stream_offset = 0,
        .base64_mode = 1,
        .max_base64_regions = 8,
    };
    try std.testing.expect(opts.mode == .font);
    try std.testing.expectEqual(@as(?u4, 9), opts.quality);
    try std.testing.expectEqual(@as(?u5, 22), opts.lgwin);
    try std.testing.expectEqual(@as(?u5, 22), opts.lgblock);
    try std.testing.expect(opts.disable_literal_context_modeling == true);
    try std.testing.expectEqual(@as(?usize, 4096), opts.size_hint);
    try std.testing.expect(opts.large_window == false);
    try std.testing.expectEqual(@as(?u2, 1), opts.npostfix);
    try std.testing.expectEqual(@as(?u7, 5), opts.ndirect);
    try std.testing.expectEqual(@as(?usize, 0), opts.stream_offset);
    try std.testing.expectEqual(@as(?u1, 1), opts.base64_mode);
    try std.testing.expectEqual(@as(?u4, 8), opts.max_base64_regions);
}

test "encoderOptions apply mode" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{ .mode = .text };
    try opts.apply(handle);
}

test "encoderOptions apply quality" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{ .quality = 6 };
    try opts.apply(handle);
}

test "encoderOptions apply lgwin" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{ .lgwin = 18 };
    try opts.apply(handle);
}

test "encoderOptions apply lgblock" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{ .lgblock = 18 };
    try opts.apply(handle);
}

test "encoderOptions apply disable_literal_context_modeling" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{ .disable_literal_context_modeling = true };
    try opts.apply(handle);
}

test "encoderOptions apply size_hint" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{ .size_hint = 1024 };
    try opts.apply(handle);
}

test "encoderOptions apply large_window" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{ .large_window = true };
    try opts.apply(handle);
}

test "encoderOptions apply npostfix" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{ .large_window = true, .npostfix = 2 };
    try opts.apply(handle);
}

test "encoderOptions apply ndirect" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{ .large_window = true, .ndirect = 12 };
    try opts.apply(handle);
}

test "encoderOptions apply stream_offset" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{ .stream_offset = 100 };
    try opts.apply(handle);
}

test "encoderOptions apply base64_mode" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{ .base64_mode = 1 };
    try opts.apply(handle);
}

test "encoderOptions apply max_base64_regions" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{ .max_base64_regions = 8 };
    try opts.apply(handle);
}

test "encoderOptions apply all" {
    const handle = c.BrotliEncoderCreateInstance(null, null, null);
    defer c.BrotliEncoderDestroyInstance(handle);
    const opts = EncoderOptions{
        .mode = .text,
        .quality = 6,
        .lgwin = 18,
        .lgblock = 18,
        .disable_literal_context_modeling = false,
        .size_hint = 2048,
    };
    try opts.apply(handle);
}
