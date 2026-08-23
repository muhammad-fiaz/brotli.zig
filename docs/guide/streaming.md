---
title: Streaming
description: Chunked compression and decompression.
---

# Streaming

## Compress

```zig
var sc = brotli.StreamingCompressor.init(allocator, .{ .quality = 9 });
defer sc.deinit();

for (chunks) |chunk| {
    const piece = try sc.process(chunk);
    defer allocator.free(piece);
    // append piece to output sink
}
const tail = try sc.finish();
defer allocator.free(tail);
// flush semantics: call sc.flush() to force blocks without ending the stream
```

## Decompress

```zig
var sd = brotli.StreamingDecompressor.init(allocator, .{});
defer sd.deinit();
sd.feed(chunk);
var buf: [4096]u8 = undefined;
const n = try sd.take(&buf);
```

## Progress

```zig
sc.setProgress(myCallback, &my_ctx);
```

Fires during large streaming compressions — wire it to a progress bar.