const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const corrupt_data = &[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00 };

    std.debug.print("Error handling demonstration:\n", .{});

    const result = brotli.decompress(allocator, corrupt_data);
    if (result) |decompressed| {
        allocator.free(decompressed);
        std.debug.print("  Unexpected success\n", .{});
    } else |err| {
        switch (err) {
            error.DecompressionFailed => {
                std.debug.print("  Caught expected error: DecompressionFailed\n", .{});
                std.debug.print("  This is correct behavior for corrupt input\n", .{});
            },
            else => {
                std.debug.print("  Unexpected error: {s}\n", .{@errorName(err)});
            },
        }
    }
}
