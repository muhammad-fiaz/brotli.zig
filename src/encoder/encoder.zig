const std = @import("std");
const c = @import("../c.zig").c;
const types = @import("../common/types.zig");
const allocator_mod = @import("../common/allocator.zig");
const options_mod = @import("options.zig");

pub const Encoder = struct {
    handle: ?*c.BrotliEncoderState,
    c_allocator: allocator_mod.CAllocator,

    pub fn init(allocator: std.mem.Allocator, options: options_mod.EncoderOptions) !Encoder {
        const ca = allocator_mod.CAllocator.fromAllocator(allocator);
        const handle = c.BrotliEncoderCreateInstance(
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

    pub fn deinit(self: *Encoder) void {
        if (self.handle) |handle| {
            c.BrotliEncoderDestroyInstance(handle);
            self.handle = null;
        }
        self.c_allocator.deinit();
    }

    pub fn setParameter(self: Encoder, param: c.BrotliEncoderParameter, value: u32) !void {
        if (self.handle == null) return error.InvalidParameter;
        if (c.BrotliEncoderSetParameter(self.handle, param, value) == c.BROTLI_FALSE)
            return error.InvalidParameter;
    }

    pub fn compressStream(self: Encoder, operation: types.EncoderOperation, input: []const u8, output: []u8) !types.StreamResult {
        if (self.handle == null) return error.InvalidParameter;

        var available_in: usize = input.len;
        var next_in: [*c]const u8 = input.ptr;
        var available_out: usize = output.len;
        var next_out: [*c]u8 = output.ptr;

        const result = c.BrotliEncoderCompressStream(
            self.handle,
            @intCast(@intFromEnum(operation)),
            &available_in,
            &next_in,
            &available_out,
            &next_out,
            null,
        );

        if (result == c.BROTLI_FALSE) return error.InvalidParameter;

        const consumed = input.len - available_in;
        const produced = output.len - available_out;

        return .{
            .bytes_consumed = consumed,
            .bytes_produced = produced,
            .has_more_output = c.BrotliEncoderHasMoreOutput(self.handle) != 0,
            .is_finished = c.BrotliEncoderIsFinished(self.handle) != 0,
        };
    }

    pub fn isFinished(self: Encoder) bool {
        if (self.handle == null) return false;
        return c.BrotliEncoderIsFinished(self.handle) != 0;
    }

    pub fn hasMoreOutput(self: Encoder) bool {
        if (self.handle == null) return false;
        return c.BrotliEncoderHasMoreOutput(self.handle) != 0;
    }

    pub fn takeOutput(self: Encoder, size: ?*usize) ?[]const u8 {
        if (self.handle == null) return null;
        const ptr = c.BrotliEncoderTakeOutput(self.handle, size);
        if (ptr == null) return null;
        const len = if (size) |s| s.* else 0;
        return ptr[0..len];
    }

    pub fn attachPreparedDictionary(self: Encoder, dict: anytype) !void {
        if (self.handle == null) return error.InvalidParameter;
        const dict_ptr: *const c.BrotliEncoderPreparedDictionary = @ptrCast(@alignCast(dict));
        if (c.BrotliEncoderAttachPreparedDictionary(self.handle, dict_ptr) == c.BROTLI_FALSE)
            return error.InvalidDictionary;
    }
};
