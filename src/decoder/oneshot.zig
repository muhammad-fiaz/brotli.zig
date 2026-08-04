const std = @import("std");
const c = @import("../c.zig").c;
const types = @import("../common/types.zig");
const allocator_mod = @import("../common/allocator.zig");
const options_mod = @import("options.zig");

pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return decompressWith(allocator, input, .{});
}

pub fn decompressWith(allocator: std.mem.Allocator, input: []const u8, options: options_mod.DecoderOptions) ![]u8 {
    const has_options = options.large_window != null or options.disable_ring_buffer_reallocation != null;
    if (!has_options) {
        return decompressOneShot(allocator, input);
    }
    return decompressStreaming(allocator, input, options);
}

fn decompressOneShot(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var buf_size: usize = input.len *| 4;
    if (buf_size < 256) buf_size = 256;

    while (true) {
        const buf = try allocator.alloc(u8, buf_size);

        var decoded_size: usize = buf_size;
        const result = c.BrotliDecoderDecompress(
            input.len,
            input.ptr,
            &decoded_size,
            buf.ptr,
        );

        if (result == c.BROTLI_DECODER_RESULT_SUCCESS) {
            if (decoded_size < buf_size) {
                return allocator.realloc(buf, decoded_size) catch buf[0..decoded_size];
            }
            return buf;
        }

        allocator.free(buf);

        if (result == c.BROTLI_DECODER_RESULT_ERROR) {
            return error.DecompressionFailed;
        }

        if (decoded_size == buf_size) {
            buf_size = buf_size *| 2;
        } else {
            return error.DecompressionFailed;
        }
    }
}

fn decompressStreaming(allocator: std.mem.Allocator, input: []const u8, options: options_mod.DecoderOptions) ![]u8 {
    const ca = allocator_mod.CAllocator.fromAllocator(allocator);
    defer ca.deinit();

    const handle = c.BrotliDecoderCreateInstance(
        @ptrCast(ca.alloc_fn),
        @ptrCast(ca.free_fn),
        ca.opaque_ptr,
    );
    if (handle == null) {
        return error.OutOfMemory;
    }
    defer c.BrotliDecoderDestroyInstance(handle);
    _ = options.apply(handle) catch {};

    var buf_size: usize = input.len *| 4;
    if (buf_size < 256) buf_size = 256;

    var input_pos: usize = 0;

    while (true) {
        const buf = try allocator.alloc(u8, buf_size);

        var available_in: usize = if (input_pos < input.len) input.len - input_pos else 0;
        var next_in: [*c]const u8 = if (input_pos < input.len) input.ptr + input_pos else undefined;
        var available_out: usize = buf_size;
        var next_out: [*c]u8 = buf.ptr;

        const result = c.BrotliDecoderDecompressStream(
            handle,
            &available_in,
            &next_in,
            &available_out,
            &next_out,
            null,
        );

        const bytes_written = buf_size - available_out;

        if (result == c.BROTLI_DECODER_RESULT_SUCCESS) {
            input_pos += available_in;
            if (bytes_written < buf_size) {
                return allocator.realloc(buf, bytes_written) catch buf[0..bytes_written];
            }
            return buf;
        }

        if (result == c.BROTLI_DECODER_RESULT_ERROR) {
            allocator.free(buf);
            return error.DecompressionFailed;
        }

        input_pos += available_in;

        if (result == c.BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT) {
            const new_buf_size = buf_size *| 2;
            const new_buf = try allocator.alloc(u8, new_buf_size);
            @memcpy(new_buf[0..bytes_written], buf[0..bytes_written]);
            allocator.free(buf);
            buf_size = new_buf_size;
            continue;
        }

        if (result == c.BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT) {
            allocator.free(buf);
            if (input_pos >= input.len) {
                return error.DecompressionFailed;
            }
            continue;
        }

        allocator.free(buf);
        return error.DecompressionFailed;
    }
}
