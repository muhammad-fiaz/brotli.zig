---
title: Compression
description: Compressing data with brotli.zig.
---

# Compression

## One-Shot

```zig
const compressed = try brotli.compress(allocator, data);
defer allocator.free(compressed);
```

## With Options

```zig
const compressed = try brotli.compressWithOptions(allocator, data, .{
    .quality = 9,       // 0..11
    .lgWin = 22,        // 10..24
    .mode = .text,
    .sizeHint = data.len,
});
defer allocator.free(compressed);
```

## Streaming

```zig
var sc = brotli.StreamingCompressor.init(allocator, .{ .quality = 9 });
defer sc.deinit();

var out = std.ArrayList(u8).empty;
defer out.deinit(allocator);
for (chunks) |chunk| {
    const piece = try sc.process(chunk);
    defer allocator.free(piece);
    try out.appendSlice(allocator, piece);
}
const tail = try sc.finishAlloc();
defer allocator.free(tail);
try out.appendSlice(allocator, tail);
```

## Instance Encoder

For parameter IDs and progress callbacks see [Encoder](../api/compressor).

## Preallocated Output

```zig
var dst = try allocator.alloc(u8, brotli.maxCompressedSize(data.len));
defer allocator.free(dst);
_ = try brotli.decompressInto(allocator, try brotli.compress(allocator, data), dst);
```

## Quality Guide

| Quality | Use case |
|---------|----------|
| 0–2 | Real-time / throughput-bound |
| 3–6 | Balanced |
| 7–9 | Ratio-sensitive |
| 10–11 | Maximum analysis (web assets) |

## Automatic Layout Selection

At quality 4+, the encoder automatically picks the best literal layout per
metablock: plain single-tree, second-order context modeling with clustered
context maps, or literal block switching. No manual configuration needed.

## Large Window

```zig
const compressed = try brotli.compressWithOptions(allocator, data, .{
    .quality = 11,
    .lgwin = 30,
    .large_window = true,
});
```

Requires `.large_window = true` on the decoder side. Not RFC-compatible.
