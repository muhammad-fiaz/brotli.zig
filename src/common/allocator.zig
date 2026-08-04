const std = @import("std");
const c = @import("../c.zig").c;

const alloc_header_size = @sizeOf(usize);

pub const CAllocator = struct {
    alloc_fn: ?*const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque,
    free_fn: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
    opaque_ptr: ?*anyopaque,
    impl: ?*AllocatorBridgeImpl,

    pub fn fromAllocator(allocator: std.mem.Allocator) CAllocator {
        const impl = AllocatorBridgeImpl.create(allocator) catch return cAllocator();
        return .{
            .alloc_fn = brotliAlloc,
            .free_fn = brotliFree,
            .opaque_ptr = @ptrCast(impl),
            .impl = impl,
        };
    }

    pub fn cAllocator() CAllocator {
        return .{
            .alloc_fn = null,
            .free_fn = null,
            .opaque_ptr = null,
            .impl = null,
        };
    }

    pub fn deinit(self: CAllocator) void {
        if (self.impl) |impl_val| {
            impl_val.deinit();
        }
    }
};

const AllocatorBridgeImpl = struct {
    allocator: std.mem.Allocator,

    fn create(allocator: std.mem.Allocator) !*AllocatorBridgeImpl {
        const impl = try allocator.create(AllocatorBridgeImpl);
        impl.* = .{ .allocator = allocator };
        return impl;
    }

    fn deinit(self: *AllocatorBridgeImpl) void {
        self.allocator.destroy(self);
    }
};

fn brotliAlloc(ctx: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    if (size == 0) return null;
    if (ctx == null) {
        const ptr = std.c.malloc(size) orelse return null;
        return @ptrCast(@alignCast(ptr));
    }
    const bridge: *AllocatorBridgeImpl = @ptrCast(@alignCast(ctx.?));
    const total = alloc_header_size + size;
    const buf = bridge.allocator.alloc(u8, total) catch return null;
    const header: *usize = @ptrCast(@alignCast(buf.ptr));
    header.* = total;
    return @ptrCast(buf.ptr + alloc_header_size);
}

fn brotliFree(ctx: ?*anyopaque, address: ?*anyopaque) callconv(.c) void {
    if (address == null) return;
    if (ctx == null) {
        std.c.free(@ptrCast(@alignCast(address.?)));
        return;
    }
    const bridge: *AllocatorBridgeImpl = @ptrCast(@alignCast(ctx.?));
    const raw_ptr: [*]u8 = @ptrCast(@alignCast(address.?));
    const header_ptr: *usize = @ptrCast(@alignCast(raw_ptr - alloc_header_size));
    const total_size = header_ptr.*;
    const start = raw_ptr - alloc_header_size;
    bridge.allocator.free(start[0..total_size]);
}
