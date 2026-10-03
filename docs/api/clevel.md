---
title: Quality Levels & Tuning
description: Compression quality levels, speed-ratio trade-offs, and mode strategies in brotli.zig.
---

# Quality Levels & Tuning

Brotli defines quality levels as numerical `u32` integers ranging from `0` to `11`. There is no dedicated enum for quality levels.

## Quality Boundaries

Defined in `src/brotli.zig`:

```zig
pub const minQuality: u32 = 0;
pub const maxQuality: u32 = 11;
pub const defaultQuality: u32 = 11;

// Uppercase aliases for C API familiarity:
pub const MIN_QUALITY: u32 = minQuality;
pub const MAX_QUALITY: u32 = maxQuality;
pub const DEFAULT_QUALITY: u32 = defaultQuality;
```

## Level Profiles & Trade-Offs

| Quality | Match Search | Lazy Evaluation | Primary Use Case |
|---|---|---|---|
| `0`..`1` | Fast greedy hash-table | Disabled | Real-time low-latency compression (e.g. streaming web sockets) |
| `2`..`4` | Multi-slot hash-table | Disabled | Fast bulk data ingest, log archival |
| `5`..`6` | Hash-chain search | Enabled | Balanced daily workloads, HTTP dynamic compression |
| `7`..`9` | Deep hash chains | Enabled | Static asset generation, release distribution |
| `10`..`11` | Optimal block splitting & context maps | Enabled | Best possible compression ratio; maximum file size reduction |

### Quality Selection Example

```zig
const brotli = @import("brotli");

// Fast real-time compression:
const fast = try brotli.compressWithOptions(allocator, data, .{
    .quality = 1,
});
defer allocator.free(fast);

// Balanced everyday compression:
const balanced = try brotli.compressWithOptions(allocator, data, .{
    .quality = 6,
});
defer allocator.free(balanced);

// Maximum ratio for static assets:
const optimal = try brotli.compressWithOptions(allocator, data, .{
    .quality = 11,
});
defer allocator.free(optimal);
```

## Sliding Window Size (`lgWin`)

The sliding window defines the maximum lookback distance for LZ77 copy commands:

```zig
pub const defaultWindow: u32 = 22;
pub const minWindowBits: u32 = 10;
pub const maxWindowBits: u32 = 24;
pub const largeMaxWindowBits: u32 = 30;
```

- Standard RFC 7932 limits `lgWin` to `10..24` (window sizes `1 KiB` to `16 MiB`).
- With `largeWindow = true`, `lgWin` may extend up to `30` (`1 GiB` sliding window).
- Max backward reference distance is `(1 << lgWin) - 16`.

```zig
const opts = brotli.CompressionOptions{
    .quality = 9,
    .lgWin = 20, // 1 MiB window: (1 << 20) - 16 bytes max distance
};
```

## Compression Modes (`Mode`)

```zig
pub const Mode = enum(u3) {
    generic = 0,
    text = 1,
    font = 2,
};
```

- `.generic`: Default tuning suitable for general binary data.
- `.text`: Tunes literal context modeling heuristics for UTF-8 and ASCII text, source code, and JSON.
- `.font`: Tunes entropy coding for WOFF 2.0 font data.

```zig
const opts = brotli.CompressionOptions{
    .quality = 11,
    .mode = .text,
    .sizeHint = input.len,
};
```
