---
title: Reusable Context
description: Multiple independent streams on one Decoder.
---

# Reusable Context

`examples/reusable_context.zig` — allocates a single `Decoder` on the
heap and decompresses two consecutive streams through it by calling
`resetForNewStream` between them.

## Client Code

```zig
const std = @import("std");
const brotli = @import("brotli");

const empty_stream = [_]u8{0x06};

fn runOne(decoder: *brotli.Decoder, data: []const u8) !usize {
    decoder.resetForNewStream();
    var input: []const u8 = data;
    var out: [64]u8 = undefined;
    var avail: []u8 = &out;
    var total: u64 = 0;
    switch (decoder.decompressStream(&input, &avail, &total)) {
        .success => {},
        else => return error.StreamFailed,
    }
    return @intCast(total);
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const decoder = try allocator.create(brotli.Decoder);
    defer allocator.destroy(decoder);
    decoder.* = brotli.Decoder.init(allocator, .{});
    defer decoder.deinit();

    const first = try runOne(decoder, &empty_stream);
    const second = try runOne(decoder, &empty_stream);
    std.debug.print(
        "two streams on one context: {d}, {d} bytes\n",
        .{ first, second },
    );
}
```

## Output

```text
two streams on one context: 0, 0 bytes
```

## Explanation

- `0x06` is a valid one-metablock Brotli stream that decodes to zero
  bytes: the metablock header has `ISLAST=1`, `ISEMPTY=1`.
- `resetForNewStream()` clears internal state (ring buffer, distance
  history, block-type tracking) without freeing the allocator-backed
  buffers, making it cheap to reuse the same `Decoder` for many streams.
- This pattern is useful in servers handling many short messages —
  allocate once, decode many.

Run it:

```bash
zig build run-reusable_context
```
