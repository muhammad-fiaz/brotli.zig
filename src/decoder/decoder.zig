const std = @import("std");
const c = @import("../c.zig").c;
const types = @import("../common/types.zig");
const allocator_mod = @import("../common/allocator.zig");
const options_mod = @import("options.zig");

pub const Decoder = struct {
    handle: ?*c.BrotliDecoderState,
    c_allocator: allocator_mod.CAllocator,

    pub fn init(allocator: std.mem.Allocator, options: options_mod.DecoderOptions) !Decoder {
        const ca = allocator_mod.CAllocator.fromAllocator(allocator);
        const handle = c.BrotliDecoderCreateInstance(
            @ptrCast(ca.alloc_fn),
            @ptrCast(ca.free_fn),
            ca.opaque_ptr,
        );
        if (handle == null) {
            ca.deinit();
            return error.OutOfMemory;
        }
        try options.apply(handle);
        return .{ .handle = handle, .c_allocator = ca };
    }

    pub fn deinit(self: *Decoder) void {
        if (self.handle) |handle| {
            c.BrotliDecoderDestroyInstance(handle);
            self.handle = null;
        }
        self.c_allocator.deinit();
    }

    pub fn setParameter(self: Decoder, param: c.BrotliDecoderParameter, value: u32) !void {
        if (self.handle == null) return error.InvalidParameter;
        if (c.BrotliDecoderSetParameter(self.handle, param, value) == c.BROTLI_FALSE)
            return error.InvalidParameter;
    }

    pub fn decompressStream(self: Decoder, input: []const u8, output: []u8) !types.DecoderResult {
        if (self.handle == null) return error.DecompressionFailed;

        var available_in: usize = input.len;
        var next_in_ptr: [*c]const u8 = input.ptr;
        var available_out: usize = output.len;
        var next_out_ptr: [*c]u8 = output.ptr;

        const result = c.BrotliDecoderDecompressStream(
            self.handle,
            &available_in,
            &next_in_ptr,
            &available_out,
            &next_out_ptr,
            null,
        );

        return switch (result) {
            c.BROTLI_DECODER_RESULT_SUCCESS => .success,
            c.BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT => .needs_more_input,
            c.BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT => .needs_more_output,
            c.BROTLI_DECODER_RESULT_ERROR => .{ .@"error" = types.DecodeError.fromNative(self.handle) },
            else => .{ .@"error" = .{ .code = .error_unreachable, .message = "unknown result" } },
        };
    }

    pub fn isUsed(self: Decoder) bool {
        if (self.handle == null) return false;
        return c.BrotliDecoderIsUsed(self.handle) != 0;
    }

    pub fn isFinished(self: Decoder) bool {
        if (self.handle == null) return false;
        return c.BrotliDecoderIsFinished(self.handle) != 0;
    }

    pub fn hasMoreOutput(self: Decoder) bool {
        if (self.handle == null) return false;
        return c.BrotliDecoderHasMoreOutput(self.handle) != 0;
    }

    pub fn takeOutput(self: Decoder, size: ?*usize) ?[]const u8 {
        if (self.handle == null) return null;
        const ptr = c.BrotliDecoderTakeOutput(self.handle, size);
        if (ptr == null) return null;
        const len = if (size) |s| s.* else 0;
        return ptr[0..len];
    }

    pub fn attachDictionary(self: Decoder, dict_type: types.DictionaryType, data: []const u8) !void {
        if (self.handle == null) return error.InvalidDictionary;
        if (c.BrotliDecoderAttachDictionary(
            self.handle,
            @intCast(@intFromEnum(dict_type)),
            data.len,
            data.ptr,
        ) == c.BROTLI_FALSE)
            return error.InvalidDictionary;
    }

    pub fn getErrorCode(self: Decoder) types.ErrorCode {
        if (self.handle == null) return .error_unreachable;
        return types.ErrorCode.fromNative(c.BrotliDecoderGetErrorCode(self.handle));
    }

    pub fn errorString(self: Decoder) []const u8 {
        if (self.handle == null) return "no decoder instance";
        const code = c.BrotliDecoderGetErrorCode(self.handle);
        const ptr = c.BrotliDecoderErrorString(code);
        return std.mem.sliceTo(ptr, 0);
    }
};
