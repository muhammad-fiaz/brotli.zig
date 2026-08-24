---
title: Strategy & Quality Levels
description: Mode enum and numeric quality levels for the Brotli encoder.
---

# Strategy & Quality Levels

There is no `CLevel` enum â€” quality levels are plain `u32`.

## Levels

Quality levels are `u32` in range `0` to `11`, with default `11`:

```zig
pub const MIN_QUALITY: u32 = 0;
pub const MAX_QUALITY: u32 = 11;
pub const DEFAULT_QUALITY: u32 = 11;

pub fn versionString() []const u8 // "0.0.3"
pub fn versionNumber() u32        // 2
```

Use with `brotli.compressWithOptions` or `StreamingCompressor`:

```zig
// Numeric quality levels
const c1 = try brotli.compressWithOptions(allocator, data, .{ .quality = 1 });  // fastest
const c5 = try brotli.compressWithOptions(allocator, data, .{ .quality = 5 });  // balanced
const c9 = try brotli.compressWithOptions(allocator, data, .{ .quality = 9 });  // good ratio
const c11 = try brotli.compressWithOptions(allocator, data, .{});               // best (default)

// Via streaming
var sc = brotli.StreamingCompressor.init(allocator, .{ .quality = 9 });
defer sc.deinit();
```

Quality trade-off (measured on pseudo-text, 512 KiB):

| Quality | Ratio | Character |
|---------|-------|-----------|
| 0â€“1 | ~21% | Fastest; greedy matching |
| 5 | ~18.5% | Balanced; lazy matching |
| 9 | ~17.5% | Deep hash-chain search |
| 11 | ~18% | Best analysis (context modeling heuristics) |

## Window Size

Backward-reference distances are bounded by `lgwin` (10..24):

```zig
const opts = brotli.CompressionOptions{
    .quality = 11,
    .lgwin = 22, // default; max distance = (1 << 22) - 16
};
```

Larger windows find more distant matches at a small memory cost. Use
`large_window = true` to accept values up to 30 for decoding interop.

## Mode

`Mode` selects text-analysis hints (mirrors `BROTLI_MODE_*`):

```zig
pub const Mode = enum(u3) {
    generic = 0,
    text = 1,
    font = 2,
};
```

Set via options:

```zig
const opts = brotli.CompressionOptions{
    .quality = 11,
    .mode = .text,
    .size_hint = input.len,
};
```
