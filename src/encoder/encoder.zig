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

    pub fn setParameter(self: Encoder, param: types.EncoderParameter, value: u32) !void {
        if (self.handle == null) return error.InvalidParameter;
        if (c.BrotliEncoderSetParameter(self.handle, @intCast(@intFromEnum(param)), value) == c.BROTLI_FALSE)
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

    pub fn attachPreparedDictionary(self: Encoder, dict: *const anyopaque) !void {
        if (self.handle == null) return error.InvalidParameter;
        const dict_ptr: *const c.BrotliEncoderPreparedDictionary = @ptrCast(@alignCast(dict));
        if (c.BrotliEncoderAttachPreparedDictionary(self.handle, dict_ptr) == c.BROTLI_FALSE)
            return error.InvalidDictionary;
    }

    pub fn estimatePeakMemoryUsage(quality: i32, lgwin: i32, input_size: usize) usize {
        return c.BrotliEncoderEstimatePeakMemoryUsage(quality, lgwin, input_size);
    }
};

pub const PreparedDictionary = struct {
    handle: ?*c.BrotliEncoderPreparedDictionary,
    c_allocator: allocator_mod.CAllocator,

    pub fn init(allocator: std.mem.Allocator, dict_type: types.DictionaryType, data: []const u8, quality: i32) !PreparedDictionary {
        const ca = allocator_mod.CAllocator.fromAllocator(allocator);
        const handle = c.BrotliEncoderPrepareDictionary(
            @intCast(@intFromEnum(dict_type)),
            data.len,
            data.ptr,
            quality,
            @ptrCast(ca.alloc_fn),
            @ptrCast(ca.free_fn),
            ca.opaque_ptr,
        );
        if (handle == null) {
            ca.deinit();
            return error.InvalidDictionary;
        }
        return .{ .handle = handle, .c_allocator = ca };
    }

    pub fn deinit(self: *PreparedDictionary) void {
        if (self.handle) |handle| {
            c.BrotliEncoderDestroyPreparedDictionary(handle);
            self.handle = null;
        }
        self.c_allocator.deinit();
    }

    pub fn getSize(self: PreparedDictionary) usize {
        if (self.handle) |handle| {
            return c.BrotliEncoderGetPreparedDictionarySize(handle);
        }
        return 0;
    }
};

test "encoder init and deinit" {
    var enc = try Encoder.init(std.testing.allocator, .{});
    defer enc.deinit();
    try std.testing.expect(enc.handle != null);
}

test "encoder setParameter quality" {
    var enc = try Encoder.init(std.testing.allocator, .{});
    defer enc.deinit();
    try enc.setParameter(.quality, 5);
}

test "encoder setParameter lgwin" {
    var enc = try Encoder.init(std.testing.allocator, .{});
    defer enc.deinit();
    try enc.setParameter(.lgwin, 18);
}

test "encoder setParameter mode" {
    var enc = try Encoder.init(std.testing.allocator, .{});
    defer enc.deinit();
    try enc.setParameter(.mode, @intCast(@intFromEnum(types.EncoderMode.text)));
}

test "encoder setParameter size_hint" {
    var enc = try Encoder.init(std.testing.allocator, .{});
    defer enc.deinit();
    try enc.setParameter(.size_hint, 1024);
}

test "encoder setParameter disable_literal_context_modeling" {
    var enc = try Encoder.init(std.testing.allocator, .{});
    defer enc.deinit();
    try enc.setParameter(.disable_literal_context_modeling, 1);
}

test "encoder setParameter large_window" {
    var enc = try Encoder.init(std.testing.allocator, .{ .large_window = true });
    defer enc.deinit();
    try enc.setParameter(.large_window, 1);
}

test "encoder setParameter npostfix" {
    var enc = try Encoder.init(std.testing.allocator, .{ .large_window = true });
    defer enc.deinit();
    try enc.setParameter(.npostfix, 2);
}

test "encoder setParameter ndirect" {
    var enc = try Encoder.init(std.testing.allocator, .{ .large_window = true });
    defer enc.deinit();
    try enc.setParameter(.ndirect, 12);
}

test "encoder setParameter stream_offset" {
    var enc = try Encoder.init(std.testing.allocator, .{});
    defer enc.deinit();
    try enc.setParameter(.stream_offset, 100);
}

test "encoder setParameter base64_mode" {
    var enc = try Encoder.init(std.testing.allocator, .{});
    defer enc.deinit();
    try enc.setParameter(.base64_mode, 1);
}

test "encoder setParameter max_base64_regions" {
    var enc = try Encoder.init(std.testing.allocator, .{});
    defer enc.deinit();
    try enc.setParameter(.max_base64_regions, 8);
}

test "encoder compressStream process" {
    var enc = try Encoder.init(std.testing.allocator, .{ .quality = 6 });
    defer enc.deinit();

    const data = "Hello, streaming compression! This is long enough to produce output";
    var output: [256]u8 = undefined;
    const result = try enc.compressStream(.process, data, &output);
    try std.testing.expect(result.bytes_consumed == data.len);
}

test "encoder compressStream finish" {
    var enc = try Encoder.init(std.testing.allocator, .{ .quality = 6 });
    defer enc.deinit();

    const data = "Finish streaming compression!";
    var output: [256]u8 = undefined;
    const result = try enc.compressStream(.finish, data, &output);
    try std.testing.expect(result.bytes_consumed == data.len);
    try std.testing.expect(result.bytes_produced > 0);
    try std.testing.expect(result.is_finished);
}

test "encoder isFinished and hasMoreOutput" {
    var enc = try Encoder.init(std.testing.allocator, .{ .quality = 6 });
    defer enc.deinit();

    try std.testing.expect(!enc.isFinished());

    const data = "Test data for encoder state queries";
    var output: [256]u8 = undefined;
    _ = try enc.compressStream(.finish, data, &output);
    try std.testing.expect(enc.isFinished());
    try std.testing.expect(!enc.hasMoreOutput());
}

test "encoder takeOutput" {
    var enc = try Encoder.init(std.testing.allocator, .{ .quality = 6 });
    defer enc.deinit();

    const data = "Take output test data";
    var output: [256]u8 = undefined;
    _ = try enc.compressStream(.finish, data, &output);

    var size: usize = 0;
    const taken = enc.takeOutput(&size);
    if (taken) |t| {
        try std.testing.expect(t.len == size);
    }
}

test "encoder compressStream flush" {
    var enc = try Encoder.init(std.testing.allocator, .{ .quality = 6 });
    defer enc.deinit();

    const data = "Flush operation test";
    var output: [256]u8 = undefined;
    const result = try enc.compressStream(.flush, data, &output);
    try std.testing.expect(result.bytes_consumed == data.len);
    try std.testing.expect(result.bytes_produced > 0);
}

test "encoder compressStream empty input" {
    var enc = try Encoder.init(std.testing.allocator, .{ .quality = 6 });
    defer enc.deinit();

    var output: [256]u8 = undefined;
    const result = try enc.compressStream(.process, &.{}, &output);
    try std.testing.expect(result.bytes_consumed == 0);
}

test "estimatePeakMemoryUsage" {
    const usage = Encoder.estimatePeakMemoryUsage(11, 22, 1024 * 1024);
    try std.testing.expect(usage > 0);
}

test "preparedDictionary init and deinit" {
    const dict_data = "shared dictionary data for compression";
    var prepared = try PreparedDictionary.init(std.testing.allocator, .raw, dict_data, 11);
    defer prepared.deinit();
    try std.testing.expect(prepared.handle != null);
}

test "preparedDictionary getSize" {
    const dict_data = "shared dictionary data for compression";
    var prepared = try PreparedDictionary.init(std.testing.allocator, .raw, dict_data, 11);
    defer prepared.deinit();
    const size = prepared.getSize();
    try std.testing.expect(size > 0);
}

test "encoder with all options" {
    var enc = try Encoder.init(std.testing.allocator, .{
        .mode = .text,
        .quality = 6,
        .lgwin = 18,
        .lgblock = 18,
        .disable_literal_context_modeling = false,
        .size_hint = 1024,
    });
    defer enc.deinit();

    const data = "Test with all encoder options applied";
    var output: [256]u8 = undefined;
    const result = try enc.compressStream(.finish, data, &output);
    try std.testing.expect(result.bytes_consumed == data.len);
    try std.testing.expect(result.bytes_produced > 0);
}

test "encoder roundtrip streaming" {
    var enc = try Encoder.init(std.testing.allocator, .{ .quality = 6 });
    defer enc.deinit();

    const data = "Streaming roundtrip test data for encoder and decoder verification";
    var enc_output: [256]u8 = undefined;
    const enc_result = try enc.compressStream(.finish, data, &enc_output);
    const compressed = enc_output[0..enc_result.bytes_produced];

    var dec = try @import("../decoder/decoder.zig").Decoder.init(std.testing.allocator, .{});
    defer dec.deinit();

    var dec_output: [256]u8 = undefined;
    const dec_result = try dec.decompressStream(compressed, &dec_output);
    switch (dec_result) {
        .success => {},
        else => return error.TestFailed,
    }
}
