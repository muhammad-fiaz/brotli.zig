const std = @import("std");
const c = @import("../c.zig").c;
const types = @import("types.zig");
const allocator_mod = @import("allocator.zig");

pub const DictionaryType = enum(c_int) {
    raw = c.BROTLI_SHARED_DICTIONARY_RAW,
    serialized = c.BROTLI_SHARED_DICTIONARY_SERIALIZED,
};

pub const SharedDictionary = struct {
    handle: ?*c.BrotliSharedDictionary,
    c_allocator: allocator_mod.CAllocator,

    pub fn init(allocator: std.mem.Allocator) !SharedDictionary {
        const ca = allocator_mod.CAllocator.fromAllocator(allocator);
        const handle = c.BrotliSharedDictionaryCreateInstance(
            @ptrCast(ca.alloc_fn),
            @ptrCast(ca.free_fn),
            ca.opaque_ptr,
        );
        if (handle == null) {
            ca.deinit();
            return error.OutOfMemory;
        }
        return .{ .handle = handle, .c_allocator = ca };
    }

    pub fn deinit(self: *SharedDictionary) void {
        if (self.handle) |handle| {
            c.BrotliSharedDictionaryDestroyInstance(handle);
            self.handle = null;
        }
        self.c_allocator.deinit();
    }

    pub fn attach(self: *SharedDictionary, dict_type: DictionaryType, data: []const u8) !void {
        if (self.handle == null) return error.InvalidDictionary;
        const result = c.BrotliSharedDictionaryAttach(
            self.handle,
            @intCast(@intFromEnum(dict_type)),
            data.len,
            data.ptr,
        );
        if (result == c.BROTLI_FALSE) return error.InvalidDictionary;
    }
};

test "sharedDictionary init and deinit" {
    var dict = try SharedDictionary.init(std.testing.allocator);
    defer dict.deinit();
    try std.testing.expect(dict.handle != null);
}

test "sharedDictionary attach raw" {
    var dict = try SharedDictionary.init(std.testing.allocator);
    defer dict.deinit();
    const data = "shared dictionary data for raw attachment";
    try dict.attach(.raw, data);
}

test "dictionaryType enum values" {
    try std.testing.expectEqual(@as(c_int, 0), @intFromEnum(DictionaryType.raw));
    try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(DictionaryType.serialized));
}
