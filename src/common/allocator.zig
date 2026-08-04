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

test "CAllocator fromAllocator" {
    var ca = CAllocator.fromAllocator(std.testing.allocator);
    defer ca.deinit();
    try std.testing.expect(ca.alloc_fn != null);
    try std.testing.expect(ca.free_fn != null);
    try std.testing.expect(ca.opaque_ptr != null);
}

test "CAllocator cAllocator" {
    const ca = CAllocator.cAllocator();
    try std.testing.expect(ca.alloc_fn == null);
    try std.testing.expect(ca.free_fn == null);
    try std.testing.expect(ca.opaque_ptr == null);
}

test "CAllocator alloc and free through bridge" {
    var ca = CAllocator.fromAllocator(std.testing.allocator);
    defer ca.deinit();

    const alloc_fn = ca.alloc_fn.?;
    const free_fn = ca.free_fn.?;
    const ctx = ca.opaque_ptr;

    const ptr = alloc_fn(ctx, 64);
    try std.testing.expect(ptr != null);

    free_fn(ctx, ptr);
}

test "CAllocator alloc zero size returns null" {
    var ca = CAllocator.fromAllocator(std.testing.allocator);
    defer ca.deinit();

    const alloc_fn = ca.alloc_fn.?;
    const ctx = ca.opaque_ptr;

    const ptr = alloc_fn(ctx, 0);
    try std.testing.expect(ptr == null);
}

test "CAllocator free null address is safe" {
    var ca = CAllocator.fromAllocator(std.testing.allocator);
    defer ca.deinit();

    const free_fn = ca.free_fn.?;
    const ctx = ca.opaque_ptr;

    free_fn(ctx, null);
}

test "CAllocator multiple alloc and free" {
    var ca = CAllocator.fromAllocator(std.testing.allocator);
    defer ca.deinit();

    const alloc_fn = ca.alloc_fn.?;
    const free_fn = ca.free_fn.?;
    const ctx = ca.opaque_ptr;

    const ptr1 = alloc_fn(ctx, 32);
    const ptr2 = alloc_fn(ctx, 64);
    const ptr3 = alloc_fn(ctx, 128);

    try std.testing.expect(ptr1 != null);
    try std.testing.expect(ptr2 != null);
    try std.testing.expect(ptr3 != null);

    free_fn(ctx, ptr1);
    free_fn(ctx, ptr2);
    free_fn(ctx, ptr3);
}
