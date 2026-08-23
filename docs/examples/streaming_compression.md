---
title: Streaming Compression
description: Chunk-based compression with StreamingCompressor.
---

# Streaming Compression

`examples/streaming_compression.zig` — feed chunks with `process`, collect
output slices, then `finish`.

## Client Code

```zig
const std = @import("std");
const brotli = @import("brotli");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var sc = brotli.StreamingCompressor.init(allocator, .{ .quality = 9 });
    defer sc.deinit();

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (chunks) |chunk| {
        const piece = try sc.process(chunk);
        defer allocator.free(piece);
        try out.appendSlice(allocator, piece);
    }
    const tail = try sc.finish();
    defer allocator.free(tail);
    try out.appendSlice(allocator, tail);
}
```

Progress callbacks: set `.progress`/`.progress_ctx` in the options or call
`setProgress` before feeding data.

Run it:

```bash
zig build run-streaming_compression
```