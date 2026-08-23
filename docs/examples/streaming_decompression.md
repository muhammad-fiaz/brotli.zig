---
title: Streaming Decompression
description: Chunk-based decompression with StreamingDecompressor.
---

# Streaming Decompression

`examples/streaming_decompression.zig` — feed compressed chunks with `feed`,
drain decoded bytes with `take`.

## Client Code

```zig
const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var sd = brotli.StreamingDecompressor.init(allocator, .{});
    defer sd.deinit();

    var out_buf: [4096]u8 = undefined;
    for (chunks) |chunk| {
        sd.feed(chunk);
        const n = try sd.take(&out_buf);
        // consume out_buf[0..n]
    }
    // Signal end-of-stream and drain the remainder.
    sd.feed(&.{});
    while (!sd.isFinished()) _ = try sd.take(&out_buf);
}
```

Run it:

```bash
zig build run-streaming_decompression
```
